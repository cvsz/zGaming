// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DAO {
    struct Proposal {
        uint256 id;
        string description;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public proposalVoters;

    uint256 public proposalCount;

    function propose(string memory desc) public {
        proposalCount++;
        proposals[proposalCount] = Proposal({
            id: proposalCount,
            description: desc,
            votesFor: 0,
            votesAgainst: 0,
            executed: false
        });
    }

    function vote(uint256 id, bool support) public {
        require(id > 0 && id <= proposalCount, "Invalid proposal");
        require(!proposalVoters[id][msg.sender], "Already voted");

        if (support) {
            proposals[id].votesFor++;
        } else {
            proposals[id].votesAgainst++;
        }

        proposalVoters[id][msg.sender] = true;
    }

    function execute(uint256 id) public {
        require(id > 0 && id <= proposalCount, "Invalid proposal");
        Proposal storage p = proposals[id];
        require(!p.executed, "Executed");

        if (p.votesFor > p.votesAgainst) {
            // apply policy (off-chain hook)
            p.executed = true;
        }
    }
}
