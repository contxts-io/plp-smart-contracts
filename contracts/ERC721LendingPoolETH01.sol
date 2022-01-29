// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;
import "./VerifySignaturePool01.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract ERC721LendingPoolETH01 is
    VerifySignaturePool01,
    OwnableUpgradeable,
    IERC721Receiver,
    PausableUpgradeable
{
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    /**
     * Pool Constants
     */
    address public _valuationSigner;

    address public _supportedCollection;


    struct PoolParams {
        uint32 interestBPS1000000XBlock;
        uint32 collateralFactorBPS;
    }

    mapping(uint256 => PoolParams) public durationSeconds_poolParam;

    /**
     * Pool Setup
     */

    function initialize(address supportedCollection) public initializer {
        __Ownable_init();
        __Pausable_init();
        _supportedCollection = supportedCollection;
    }

    function setDurationParam(uint256 duration, PoolParams calldata ppm)
        public
        onlyOwner
    {
        durationSeconds_poolParam[duration] = ppm;
    }

    function setValuationSigner(address valuationSigner) public onlyOwner {
        _valuationSigner = valuationSigner;
    }

    function pause() public onlyOwner {
      _pause();
    }

    function unpause() public onlyOwner {
      _unpause();
    }

    /**
     * Storage and Events
     */

    struct LoanTerms {
        uint256 loanStartBlock;
        uint256 loanExpireTimestamp;
        uint32 interestBPS1000000XBlock;
        uint32 maxLTVBPS;
        uint256 borrowedWei;
        uint256 returnedWei;
        uint256 accuredInterestWei;
        uint256 repaidInterestWei;
        address borrower;
    }

    mapping(uint256 => LoanTerms) public _loans;
    event LoanInitiated(
        address indexed user,
        address indexed erc721,
        uint256 indexed nftID,
        LoanTerms loan
    );
    event LoanTermsChanged(
        address indexed user,
        address indexed erc721,
        uint256 indexed nftID,
        LoanTerms oldTerms,
        LoanTerms newTerms
    );
    event Liquidation(
        address indexed user,
        address indexed erc721,
        uint256 indexed nftID,
        uint256 liquidated_at,
        address liquidator,
        uint256 reason
    );

    /**
     * View functions
     */

    function nftHasLoan(uint256 nftID) internal view returns (bool) {
        return _loans[nftID].borrowedWei > _loans[nftID].returnedWei;
    }

    function outstanding(uint256 nftID) public view returns (uint256) {
        // do not lump the interest
        if (_loans[nftID].borrowedWei <= _loans[nftID].returnedWei) return 0;
        uint256 newAccuredInterestWei = ((block.number -
            _loans[nftID].loanStartBlock) *
            (_loans[nftID].borrowedWei - _loans[nftID].returnedWei) *
            _loans[nftID].interestBPS1000000XBlock) / 10000000000;
        return
            (_loans[nftID].borrowedWei - _loans[nftID].returnedWei) +
            (_loans[nftID].accuredInterestWei -
                _loans[nftID].repaidInterestWei) +
            newAccuredInterestWei;
    }

    function isUnHealthyLoan(uint256 nftID)
        public
        view
        returns (bool, uint256)
    {
        require(nftHasLoan(nftID), "nft does not have active loan");
        bool isExpired = block.timestamp > _loans[nftID].loanExpireTimestamp &&
            outstanding(nftID) > 0;
        return (isExpired, 0);
    }

    /**
     * Loan origination
     */

    function borrowETH(
        uint256 valuation,
        uint256 nftID,
        uint256 loanDurationSeconds,
        uint256 expireAtBlock,
        uint256 borrowedWei,
        bytes memory signature
    ) public whenNotPaused {
        require(
            verify(
                _supportedCollection,
                nftID,
                valuation,
                expireAtBlock,
                _valuationSigner,
                signature
            ),
            "SignatureVerifier: fake valuation provided!"
        );
        require(!nftHasLoan(nftID), "NFT already has loan!");
        uint32 maxLTVBPS = durationSeconds_poolParam[loanDurationSeconds]
            .collateralFactorBPS;
        require(maxLTVBPS > 0, "Duration not supported");
        require(
            IERC721(_supportedCollection).ownerOf(nftID) == msg.sender,
            "Stealer!"
        );
        require(block.number < expireAtBlock, "Valuation expired");
        require(
            borrowedWei <= (valuation * maxLTVBPS) / 10_000,
            "Can't borrow more than max LTV"
        );
        require(borrowedWei < address(this).balance, "not enough money");
        
        _loans[nftID] = LoanTerms(
            block.number,
            block.timestamp + loanDurationSeconds,
            durationSeconds_poolParam[loanDurationSeconds].interestBPS1000000XBlock,
            maxLTVBPS,
            borrowedWei,
            0,
            0,
            0,
            msg.sender
        );
        emit LoanInitiated(
            msg.sender,
            _supportedCollection,
            nftID,
            _loans[nftID]
        );
        IERC721(_supportedCollection).transferFrom(
            msg.sender,
            address(this),
            nftID
        );

        (bool success, ) = msg.sender.call{value: borrowedWei}("");
        require(success, "cannot send ether");
    }

    /**
     * Repay
     */

    // repay change loan terms, renew loan start, fix interest to borrowed amount, dont renew loan expiry
    function repayETH(uint256 nftID) public payable whenNotPaused {
        require(nftHasLoan(nftID), "NFT does not have active loan");
        uint256 repayAmount = msg.value;
        LoanTerms memory oldLoanTerms = _loans[nftID];
        // require(repayAmount > outstanding(nftID), "repay amount exceed outstanding");
        if (repayAmount >= outstanding(nftID)) {
            uint256 toBeTransferred = repayAmount - outstanding(nftID);
            repayAmount = outstanding(nftID);
            // _loans[nftID].accuredInterestWei =
            //     outstanding(nftID) -
            //     _loans[nftID].borrowedWei;
            _loans[nftID].returnedWei = _loans[nftID].borrowedWei;
            // _loans[nftID].repaidInterestWei = _loans[nftID].accuredInterestWei;
            IERC721(_supportedCollection).transferFrom(
                address(this),
                _loans[nftID].borrower,
                nftID
            );
            (bool success, ) = msg.sender.call{value: toBeTransferred}("");
            require(success, "cannot send ether");
        } else {
            // lump in interest
            //_loans[nftID].previousBorrowedWei = _loans[nftID].borrowedWei;
            _loans[nftID].accuredInterestWei +=
                ((block.number - _loans[nftID].loanStartBlock) *
                    (_loans[nftID].borrowedWei - _loans[nftID].returnedWei) *
                    _loans[nftID].interestBPS1000000XBlock) /
                10000000000;
            uint256 outstandingInterest = _loans[nftID].accuredInterestWei -
                _loans[nftID].repaidInterestWei;
            if (repayAmount > outstandingInterest) {
                _loans[nftID].repaidInterestWei = _loans[nftID]
                    .accuredInterestWei;
                _loans[nftID].returnedWei += (repayAmount -
                    outstandingInterest);
            } else {
                _loans[nftID].repaidInterestWei += repayAmount;
            }
            // restart interest calculation
            _loans[nftID].loanStartBlock = block.number;
        }
        emit LoanTermsChanged(
            _loans[nftID].borrower,
            _supportedCollection,
            nftID,
            oldLoanTerms,
            _loans[nftID]
        );
    }

    /**
     * Liquidation
     ( warning! If it is not only owner. miners can always fast forward the clock by 15 seconds to liquidate anything before us)
     */

    function liquidateLoan(uint256 nftID) public onlyOwner {
        require(nftHasLoan(nftID), "nft does not have active loan");
        (bool unhealthy, uint256 reason) = isUnHealthyLoan(nftID);
        require(unhealthy, "can't liquidate this loan");
        LoanTerms memory oldLoanTerms = _loans[nftID];
        _loans[nftID].returnedWei = _loans[nftID].borrowedWei;
        emit Liquidation(
            _loans[nftID].borrower,
            _supportedCollection,
            nftID,
            block.timestamp,
            msg.sender,
            reason
        );
        IERC721(_supportedCollection).safeTransferFrom(
            address(this),
            owner(),
            nftID
        );
        emit LoanTermsChanged(
            _loans[nftID].borrower,
            _supportedCollection,
            nftID,
            oldLoanTerms,
            _loans[nftID]
        );
    }

    receive() external payable {
        // React to receiving ether
    }

    /**
     * Admin functions
     */

    function withdraw(uint256 amount) public onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "cannot send ether");
    }

    function withdrawERC20(address currency, uint256 amount) public onlyOwner {
        IERC20(currency).transfer(owner(), amount);
    }

    function withdrawERC721(address collection, uint256 nftID)
        public
        onlyOwner
    {
        require(
            !(collection == _supportedCollection && nftHasLoan(nftID)),
            "no stealing"
        );
        IERC721(collection).safeTransferFrom(address(this), owner(), nftID);
    }

    /**
     * Pool is not supposed to be used again after calling this function
     */
    function emergencyWithdrawLoanCollateral(uint256 nftID, bytes memory signature, uint8 withdrawToOwner)
        public
        whenPaused onlyOwner
    {
        require(
            nftHasLoan(nftID),
            "could be withdrawn using withdrawERC721"
        );
        require(
            verify(
                _supportedCollection,
                nftID,
                238888 + withdrawToOwner,
                238888 + withdrawToOwner,
                _loans[nftID].borrower,
                signature
            ),
            "SignatureVerifier: fake signature provided!"
        );
        if (withdrawToOwner == 1) {
          IERC721(_supportedCollection).safeTransferFrom(address(this), owner(), nftID);
        } else if (withdrawToOwner == 0) {
          IERC721(_supportedCollection).safeTransferFrom(address(this), _loans[nftID].borrower, nftID);
        }
        
    }
}
