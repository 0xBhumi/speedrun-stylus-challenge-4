export const IMultiSig = [  
  "function numConfirmationsRequired() external view returns (uint256)",

  "function deposit() external payable",

  "function submitTransaction(address to, uint256 value, bytes calldata data) external",

  "function initialize(address[] memory owners, uint256 num_confirmations_required) external",

  "function executeTransaction(uint256 tx_index) external",

  "function confirmTransaction(uint256 tx_index) external",

  "function revokeConfirmation(uint256 tx_index) external",

  "function isOwner(address check_address) external view returns (bool)",

  "function getTransactionCount() external view returns (uint256)",

  "function getTransaction(uint256 tx_index) external view returns (tuple(address to,uint256 value,bytes data,bool executed,uint256 numConfirmations))",

  "function getOwners() external view returns (address[])",

  "error AlreadyInitialized",

  "error ZeroOwners",

  "error InvaildConfirmationNumber",

  "error InvalidOwner",

  "error OwnerNotUnique",

  "error NotOwner",

  "error TxDoesNotExist",

  "error TxAlreadyExecuted",

  "error TxAlreadyConfirmed",

  "error TxNotConfirmed",

  "error ConfirmationNumberNotEnough",

  "error ExecuteFailed",
];
