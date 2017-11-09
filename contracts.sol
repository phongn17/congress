pragma solidity ^0.4.15;


contract Owned {
    address public owner;

    function Owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}


interface Token {
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
}


contract TokenRecipient {
    event ReceivedEther(address sender, uint amount);
    event ReceivedTokens(address _from, uint256 _value, address _token, bytes _extraData);

    function receiveApproval(
        address _from, uint256 _value, address _token, bytes _extraData) public 
    {
        Token token = Token(_token);
        require(token.transferFrom(_from, this, _value));
        ReceivedTokens(
            _from, _value, _token, _extraData
        );
    }

    function() payable public {
        ReceivedEther(msg.sender, msg.value);
    }
}


contract Congress is Owned, TokenRecipient {
    uint public minimumQuorum;
}