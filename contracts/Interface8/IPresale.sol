// SPDX-License-Identifier: GPL-3.0-or-later Or MIT

pragma solidity ^0.8.0;

interface IPresale{

    function updateKyc(bool _isKyc) external;

    function updateAudit(bool _isAudit) external;
}