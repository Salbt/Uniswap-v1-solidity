// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Exchange } from "./uniswap_v1_exchange.sol";

contract Factory {
    
    uint256 public tokenCount;
    mapping(address => address) token_to_exchange;
    mapping(address => address) exchange_to_token;
    mapping(uint256 => address) id_to_token;

    event NewExchange(address indexed  token, address indexed exchange);


    function createExchange(address token) public returns(address) {
        require(token != address(0));
        require(token_to_exchange[token] == address(0));
        Exchange exchange = new Exchange(token, 3);
        token_to_exchange[token] = address(exchange);
        exchange_to_token[address(exchange)] = token;
        uint256 token_id = tokenCount + 1;
        id_to_token[token_id] = token;
        emit NewExchange(token, address(exchange));
        return address(exchange);
    }

    function getExchange(address token) public view returns (address) {
        return token_to_exchange[token];
    }

    function getToken(address exchange) public view returns (address) {
        return exchange_to_token[exchange];
    }

    function getTokenWithId(uint256 tokenId) public view returns (address) {
        return id_to_token[tokenId];
    }

}
