import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract Token is ERC20 {
  constructor() ERC20("DSF", "DSF") {
    _mint(msg.sender, 8888888888888888888888);
  }
}