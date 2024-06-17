// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {IBrevisProof} from "./IBrevisProof.sol";
import {Brevis} from "./Lib.sol";

abstract contract BrevisApp {
    IBrevisProof public immutable brevisProof;

    constructor(IBrevisProof _brevisProof) {
        brevisProof = _brevisProof;
    }

    function validateRequest(bytes32 _requestId, uint64 _chainId, Brevis.ExtractInfos memory _extractInfos)
        public
        view
        virtual
        returns (bool)
    {
        brevisProof.validateRequest(_requestId, _chainId, _extractInfos);
        return true;
    }

    function brevisCallback(bytes32 _requestId, bytes calldata _appCircuitOutput) external {
        (bytes32 appCommitHash, bytes32 appVkHash) = IBrevisProof(brevisProof).getProofAppData(_requestId);
        require(appCommitHash == keccak256(_appCircuitOutput), "BrevisApp: invalid appCommitHash");
        handleProofResult(_requestId, appVkHash, _appCircuitOutput);
    }

    function handleProofResult(bytes32 _requestId, bytes32 _appVkHash, bytes calldata _appCircuitOutput)
        internal
        virtual
    {}
}
