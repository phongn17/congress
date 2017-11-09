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
    uint public debatingPeriodInMinutes;
    int public majorityMargin;
    Proposal[] public proposals;
    uint public numProposals;
    mapping (address => uint) public memberId;
    Member[] public members;

    event ProposalAdded(uint proposalId, address recipient, uint amount, string description);
    event Voted(uint proposalId, bool position, address voter, string justification);
    event ProposalTallied(uint proposalId, int result, uint quorum, bool active);
    event MembershipChanged(address member, bool isMember);
    event ChangeOfRules(uint newMinimumQuorum, uint newDebatingPeriodInMinutes, int newMajorityMargin);

    struct Proposal {
        address recipient;
        uint amount;
        string description;
        uint votingDeadline;
        bool executed;
        bool proposalPassed;
        uint numberOfVotes;
        int currentResult;
        bytes32 proposalHash;
        Vote[] votes; 
        mapping (address => bool) voted;
    }

    struct Member {
        address member;
        string name;
        uint memberSince;
    }

    struct Vote {
        bool inSupport;
        address voter;
        string justification;
    }

    // modifier that allows only shareholders to vote and create new proposals
    modifier onlyMembers {
        require(memberId[msg.sender] != 0);
        _;
    }

    function Congress(uint minimumQuorumForProposals, uint minutesForDebate, int marginOfVotesForMajority) payable public {
        changeVotingRules(minimumQuorumForProposals, minutesForDebate, marginOfVotesForMajority);
        // It's necessary to add an empty first member
        addMember(0, "");
        // and let's add the founder, to save a step later
        addMember(owner, "founder");
    }

    function addMember(address targetMember, string memberName) onlyOwner public {
        uint id = memberId[targetMember];

        if (id == 0) {
            memberId[targetMember] = members.length;
            id = members.length++;
        }

        members[id] = Member({ member: targetMember, memberSince: now, name: memberName });
        MembershipChanged(targetMember, true);
    }

    function removeMember(address targetMember) onlyOwner public {
        require(memberId[targetMember] != 0);

        for (uint idx = memberId[targetMember]; idx < members.length - 1; idx++) {
            members[idx] = members[idx + 1];
        }

        delete members[members.length - 1];
        members.length--;
    }

    /**
     * Make so that proposals need to be discussed for at least minutesForDebate minutes, have at least minimumQrorumForProposals votes, and 
     * have 50% + marginOfVotesForMajority votes to be executes
     */
    function changeVotingRules(uint minimumQuorumProposals, uint minutesForDebate, int marginOfVotesForMajority) onlyOwner public {
        minimumQuorum = minimumQuorumProposals;
        debatingPeriodInMinutes = minutesForDebate;
        majorityMargin = marginOfVotesForMajority;

        ChangeOfRules(minimumQuorum, debatingPeriodInMinutes, majorityMargin);
    }

    /**
     * Propose to send amount / 1e18 ethers to beneficiary for job description 
     */
    function newProposal(address beneficiary, uint amount, string jobDescription, bytes transactionBytecode) onlyMembers public returns (uint proposalId) {
        proposalId = proposals.length++;
        Proposal storage proposal = proposals[proposalId];
        proposal.recipient = beneficiary;
        proposal.amount = amount;
        proposal.description = jobDescription;
        proposal.proposalHash = keccak256(beneficiary, amount, transactionBytecode);
        proposal.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        proposal.executed = false;
        proposal.proposalPassed = false;
        proposal.numberOfVotes = 0;
        ProposalAdded(proposalId, beneficiary, amount, jobDescription);
        numProposals = proposalId + 1;
    }

    /**
     * Propose to send etherAmount ether to beneficiary for job description
     */
    function newProposalInEther(address beneficiary, uint etherAmount, string jobDescription, bytes transactionBytecode) onlyMembers public returns (uint proposalId) {
         return newProposal(beneficiary, etherAmount * 1 ether, jobDescription, transactionBytecode);
     }

     /**
      * Check if a proposal code matches
      */
    function checkProposalCode(uint proposalId, address beneficiary, uint amount, bytes transactionBytecode) constant public returns (bool codeChecksOut) {
        Proposal storage proposal = proposals[proposalId];

        return proposal.proposalHash == keccak256(beneficiary, amount, transactionBytecode);
    }

    /**
     * Log a vote for a proposal
     */
    function vote(uint proposalId, bool supportsProposal, string justificationText) onlyMembers public returns (uint voteId) {
        Proposal storage proposal = proposals[proposalId];
        // if has already voted, cancel
        require(!proposal.voted[msg.sender]);
        // set this voter as having voted
        proposal.voted[msg.sender] = true;
        // increase the number of votes 
        proposal.numberOfVotes++;
        if (supportsProposal) // if they support the proposal
            proposal.currentResult++; // increase the score
        else
            proposal.currentResult--; // decrease the score

        // create a log of this event
        Voted(proposalId, supportsProposal, msg.sender, justificationText);

        return proposal.numberOfVotes;
    }

    /**
     * count the votes proposal and execute it if approved
     */
    function executeProposal(uint proposalId, bytes transactionBytecode) public {
        Proposal storage proposal = proposals[proposalId];
        require(now > proposal.votingDeadline && !proposal.executed && proposal.proposalHash == keccak256(proposal.recipient, proposal.amount, transactionBytecode) && proposal.numberOfVotes >= minimumQuorum);
        if (proposal.currentResult > majorityMargin) {
            proposal.executed = true;
            require(proposal.recipient.call.value(proposal.amount)(transactionBytecode));
            proposal.proposalPassed = true;
        }
        else
            proposal.proposalPassed = false;

        ProposalTallied(
            proposalId, proposal.currentResult, proposal.numberOfVotes, proposal.proposalPassed
        );
    }
}