// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

interface IFactory {
    function getExchange(address) external view returns (address);
}

interface IExchange{
    function getEthTokenOutPrice(uint256) external view returns (uint256);
    function ethToTokenTransferInput(uint256, uint256, address)  external payable  returns (uint256);
    function ethToTokenTransferOutput(uint256, uint256, address) external payable  returns (uint256);
}

contract Exchange is ERC20, ERC20Permit{


    IERC20 public token;
    IFactory factory;
    // set fee
    uint256 public fee;

    event TokenPurchase(address indexed buyer, uint256 indexed eth_sold, uint256 indexed token_bought);
    event EthPurchase(address indexed buyer, uint256 indexed token_sold, uint256 indexed eth_bought);
    event AddLiquidity(address indexed provider, uint256 indexed eth_amount, uint256 indexed token__amount);
    event RemoveLiquidity(address indexed provider, uint256 indexed eth_amount, uint256 indexed token__amount);


    constructor (address token_addr, uint256 _fee) ERC20("uniswap", "uni") ERC20Permit("uniswap")
    {
        require(token_addr != address(0), "token address can't equal zero");
        token = IERC20(token_addr);
        factory = IFactory(msg.sender);
        fee = _fee;
    }

    function addLiquidity(
        uint256 min_liquidity, 
        uint256 max_tokens, 
        uint256 deadline
        ) payable 
        external 
        returns (uint256) 
    {
        require(deadline > block.timestamp, "block time exceeded deadline");
        require(msg.value > 0 && max_tokens > 0, "add token or eth of amount can't equal zero");
        uint256 total_liquidity = totalSupply();
        if (total_liquidity > 0) {
            require(min_liquidity > 0, "min_liquidity can't equal zero");
            // eth_reserve = x, token_reserve = y
            uint256 eth_reserve = address(this).balance - msg.value;
            uint256 token_reserve = token.balanceOf(address(this));
            // token_amount = dy = dx/x * y + 1 
            uint256 token_amount = msg.value * token_reserve / eth_reserve + 1;
            // eth_amount = S = dx/x * T
            uint256 liuiqity_minted = msg.value * total_liquidity / eth_reserve;
            require(max_tokens > token_amount, "max_token does not meet the addLiquidity requirement");
            require(liuiqity_minted > min_liquidity, "min_liquidity does not meet the addLiquidity requirement");
            // mint liquidity
            _mint(msg.sender, liuiqity_minted);
            require(token.transferFrom(msg.sender, address(this), token_amount), "transferFrom failed");
            emit AddLiquidity(msg.sender, msg.value, token_amount);
            return liuiqity_minted;
        } else {
            require(msg.value >= 1000000000, "init_liquidity must input 1000000000 wei");
            require(factory.getExchange(address(token)) == address(this), "factory not create the pair");
            uint256 token_amount = max_tokens;
            // initial liquidity = x wei
            uint256 initial_liquidity = address(this).balance;
            // mint liquidity
            _mint(msg.sender, initial_liquidity);
            require(token.transferFrom(msg.sender, address(this), token_amount), "transferFrom failed");
            emit AddLiquidity(msg.sender, msg.value, token_amount);
            return initial_liquidity;
        }
    }

    function removeLiquidity(
        uint256 amount, 
        uint256 min_eth, 
        uint256 min_tokens, 
        uint256 deadline
        ) payable 
        external 
        returns (uint256 eth_amount, uint256 token_amount) 
    {
        require(amount > 0, "removeLiquidity must greater than zero");
        require(deadline > block.timestamp, "block time exceeded deadline");
        require(min_eth > 0 && min_tokens > 0, "add token or eth of amount can't equal zero");
        uint256 total_liquidity = this.totalSupply();
        require(total_liquidity != 0, "total_liquidity equal zero");
        uint256 token_reserve = token.balanceOf(address(this));
        // eth_amount = dx = x * S / T
        eth_amount = amount * address(this).balance / total_liquidity;
        // token_amount = dy = y * S / T
        token_amount = amount * token_reserve / total_liquidity;
        require(eth_amount > min_eth && token_amount > min_tokens, "min_token or min_tokens does not meet the removeLiquidity requirement" );
        // burn liquidity
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
        require(token.transfer(msg.sender, token_amount), "transferFrom failed");
        emit RemoveLiquidity(msg.sender, eth_amount, token_amount);
    } 

    function getInputPrice(
        uint256 input_amount, 
        uint256 input_reserve, 
        uint256 output_reserve
        ) private 
        view 
        returns (uint256) 
    {
        require(input_reserve > 0 && output_reserve > 0, "input or output equal zero");
        // fee < 1000, not write require logic
        uint256 input_amount_with_fee = 1 wei;
        input_amount_with_fee = input_amount * (1000 - fee);
        uint256 numrator = input_amount_with_fee * output_reserve;
        uint256 denominator = ( input_reserve * 1000 ) + input_amount_with_fee;
        // dy = y * dx * (1000-fee) / (x * 1000 + dx * (1000 -fee))
        return numrator / denominator;

    }

    function getOutputPrice(
        uint256 output_amount, 
        uint256 input_reserve, 
        uint256 output_reserve
        ) private 
        pure 
        returns (uint256) 
    {
        require(input_reserve > 0 && output_reserve > 0, "input or output equal zero");
        uint256 numrator = input_reserve * output_amount * 1000;
        uint256 denominator = (output_reserve - output_amount) * 997;
        return numrator / denominator + 1;
    }

    function ethToTokenInput(
        uint256 eth_sold, 
        uint256 min_token, 
        uint256 deadline, 
        address buyer, 
        address recipient
        ) private 
        returns (uint256) 
    {
        require(deadline >= block.timestamp, "block time exceeded deadline");
        uint256 token_reserve = token.balanceOf(address(this));
        // eth_sold = dx, x = address(this).balance, y = token_reserve
        uint256 tokens_bought = getInputPrice(eth_sold , address(this).balance - eth_sold, token_reserve);
        require(tokens_bought >= min_token, "token price less than min_token");
        require(token.transfer(recipient, tokens_bought), "transferFrom failed");
        emit TokenPurchase(buyer, eth_sold, tokens_bought);
        return tokens_bought;
    }

    function defaultConvert() public payable {
        ethToTokenInput(msg.value , 1, block.timestamp, msg.sender, msg.sender);
    }

    function ethToTokenSwapInput(
        uint256 min_tokens, 
        uint256 deadline
        ) public 
        payable 
        returns (uint256) 
    {
        return ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender);
    }

    function ethToTransferInput(
        uint256 min_tokens, 
        uint256 deadline, 
        address recipient
        ) public 
        payable 
        returns (uint256) 
    {
        require(recipient != address(this) && recipient != address(0), "recipient can't equal itself or zero");
        return ethToTokenInput(msg.value, min_tokens, deadline, msg.sender, recipient);
    }

    function ethToTokenOutput(
        uint256 tokens_bought, 
        uint256 max_eth, 
        uint256 deadline, 
        address buyer, 
        address recipient
        ) private 
        returns (uint256) 
    {
        require(deadline >= block.timestamp, "block time exceeded deadline");
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 eth_sold = getOutputPrice(tokens_bought, address(this).balance - max_eth, token_reserve);
        uint256 eth_refund = max_eth - eth_sold;
        if (eth_refund > 0) {
            payable (address(msg.sender)).transfer(eth_refund);
        }
        require(token.transfer(recipient, tokens_bought), "transfer failed");
        emit TokenPurchase(buyer, eth_sold, tokens_bought);
        return eth_sold;
    }

    function ethToTokenSwapOut(
        uint256 tokens_bought, 
        uint256 deadline
        ) public 
        payable 
        returns (uint256) 
    {
        return ethToTokenOutput(tokens_bought, msg.value, deadline, msg.sender, msg.sender);
    }

    function ethToTokenTransferOutput(
        uint256 tokens_bought, 
        uint256 deadline, 
        address recipient
        ) public 
        payable 
        returns (uint256) 
    {
        require(recipient != address(this) && recipient != address(0), "recipient cna't equal zero or itself");
        return ethToTokenOutput(tokens_bought, msg.value , deadline, msg.sender, recipient);
    }

    function tokenToEthInput(
        uint256 tokens_sold, 
        uint256 min_eth, 
        uint256 deadline, 
        address buyer, 
        address recipient
        ) private 
        returns (uint256) 
    {
        require(deadline >= block.timestamp, "block time exceeded deadline");
        uint256 token_reserve = token.balanceOf(address(this));
        // token_reserve = y, tokens_sold = dy,  address(this).balance = x
        uint eth_bought = getInputPrice(token_reserve, token_reserve, address(this).balance);
        require(eth_bought >= min_eth, "eth price less than min_token");
        payable (recipient).transfer(eth_bought);
        emit EthPurchase(buyer, tokens_sold, eth_bought);
        return eth_bought;
    }

    function tokenTokenSwapInput(
        uint256 tokens_sold, 
        uint256 min_eth, 
        uint256 deadline
        ) public 
        returns (uint256) 
    {
        return tokenToEthInput(tokens_sold, min_eth, deadline, msg.sender, msg.sender);
    }

    function tokenToEthTransferInput(
        uint256 tokens_sold, 
        uint256 min_eth, 
        uint256 deadline, 
        address buyer,
        address recipient
        ) public  
        returns (uint256) 
    {
        require(recipient != address(this) && recipient != address(0), "recipient cna't equal zero or itself");
        return tokenToEthInput(tokens_sold, min_eth, deadline, buyer, recipient);
    }

    function tokenToEthOutput(
        uint256 eth_bought,
        uint256 max_tokens,
        uint256 deadline,
        address buyer,
        address recipient
    ) private 
    returns (uint256) {
        require(deadline >= block.timestamp, "block time exceeded deadline");
        uint256 token_reserve = token.balanceOf(address(this));
        uint256 tokens_sold = getOutputPrice(eth_bought, token_reserve, address(this).balance);
        require(max_tokens >= tokens_sold, "token price grater than max_token");
        payable (recipient).transfer(eth_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold), "transfer failed");
        emit TokenPurchase(buyer, tokens_sold, eth_bought);
        return tokens_sold;
    }

    function tokenToEthSwapOutput(
        uint256 eth_bought,
        uint256 max_tokens,
        uint256 deadline
        ) public 
        returns (uint256) 
    {
        return tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, msg.sender);
    }

    function tokenToEthTransferOutput(
        uint256 eth_bought,
        uint256 max_tokens,
        uint256 deadline,
        address recipient
    ) public 
    returns (uint256) 
    {
        require(recipient != address(this) && recipient != address(0), "recipient cna't equal zero or itself");
        return tokenToEthOutput(eth_bought, max_tokens, deadline, msg.sender, recipient);
    }

    function tokenToTokenInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address buyer,
        address recipient,
        address exchange_addr
        ) private 
        returns (uint256)
    {
        require(deadline >= block.timestamp, "block time exceeded deadline");
        require(min_tokens_bought > 0 && min_eth_bought > 0, "min_tokens_bought and min_eth_bought can't equal zero");
        require(exchange_addr != address(0) && exchange_addr != address(this), "token_addr cna't equal zero or itself");
        uint256 tokens_reserve = token.balanceOf(address(this));
        uint256 eth_bought = getInputPrice(tokens_sold, tokens_reserve, address(this).balance);
        require(eth_bought >= min_eth_bought);
        require(token.transferFrom(buyer, address(this), tokens_sold), "transferFrom failed");
        uint256 tokens_bought = IExchange(exchange_addr).ethToTokenTransferInput{value: eth_bought}(min_tokens_bought, deadline, recipient);
        emit EthPurchase(buyer, tokens_sold, eth_bought);
        return tokens_bought;

    }

    function tokenToTokenSwapInput(
        uint256 tokens_sold, 
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address token_addr
        ) public  
        returns (uint256) 
    {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr);
    }

    function tokenToTokenTransferInput(
        uint256 tokens_sold, 
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint256 deadline,
        address recipient,
        address token_addr
    ) public 
    returns (uint256)
    {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, recipient, exchange_addr);
    }

    function tokenToTokenOutput(
        uint256 tokens_bought, 
        uint256 max_tokens_sold, 
        uint256 max_eth_sold, 
        uint256 deadline,
        address buyer,
        address recipient,
        address exchange_addr
        ) private
        returns (uint256) 
        {
            require(deadline >= block.timestamp, "block time exceeded deadline");
            require(max_tokens_sold > 0 && max_eth_sold > 0, "max_tokens_bought and max_eth_bought can't equal zero");
            require(exchange_addr != address(0) && exchange_addr != address(this), "token_addr cna't equal zero or itself");
            uint256 tokens_reserve = token.balanceOf(address(this));
            uint256 eth_bought = IExchange(exchange_addr).getEthTokenOutPrice(tokens_bought);
            uint256 tokens_sold = getOutputPrice(eth_bought, tokens_reserve, address(this).balance);
            require(max_tokens_sold >= tokens_sold && max_eth_sold >= eth_bought, "token_sold or eth_bought of price greater than max price");
            require(token.transferFrom(buyer, address(this), tokens_sold), "transferFrom failed");
            uint256 eth_sold = IExchange(exchange_addr).ethToTokenTransferInput{value: eth_bought}(tokens_bought, deadline, recipient);
            emit EthPurchase(buyer, tokens_sold, eth_bought);
            return eth_sold;
        }


    function tokenToTokenSwapOutput(
        uint256 tokens_bought, 
        uint256 max_tokens_sold, 
        uint256 max_eth_sold, 
        uint256 deadline,
        address token_addr
        ) public 
        returns (uint256) 
    {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, msg.sender, exchange_addr);
    }

    function tokenToTokenTransfetOutput(
        uint256 tokens_bought, 
        uint256 max_tokens_sold, 
        uint256 max_eth_sold,
        uint256 deadline,
        address recipient,
        address token_addr
        ) public 
        returns (uint256) 
    {
        address exchange_addr = factory.getExchange(token_addr);
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr);
    } 

    function tokenToExchangeSwapInput(
        uint256 tokens_sold,
        uint256 min_tokens_bought,
        uint256 min_eth_bought,
        uint deadline,
        address exchange_addr
        ) public 
        returns (uint) 
    {
        return tokenToTokenInput(tokens_sold, min_tokens_bought, min_eth_bought, deadline, msg.sender, msg.sender, exchange_addr);
    }

    function tokenToExchangeTransferOutput(
        uint256 tokens_bought,
        uint256 max_tokens_sold,
        uint256 max_eth_sold,
        uint256 deadline,
        address recipient,
        address exchange_addr
        ) public 
        returns (uint256) 
    {
        require(recipient != address(this), "recipient can't be itself");
        return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_eth_sold, deadline, msg.sender, recipient, exchange_addr);
    }

    function getEthToTokenInputPirce(
        uint256 eth_sold
        ) public 
        view
        returns (uint256) 
    {
        require(eth_sold > 0, "eth_sold can't be zero");
        uint256 token_reserve = token.balanceOf(address(this));
        return getInputPrice(eth_sold, address(this).balance, token_reserve);
    }

    function getEthToTokenOutputPirce(
        uint256 token_bought
        ) public 
        view
        returns (uint256) 
    {
        require(token_bought > 0, "token_bought can't be zero");
        uint256 token_reserve = token.balanceOf(address(this));
        return getOutputPrice(token_bought, address(this).balance, token_reserve);
    }

    function getTokenToEthInputPirce(
        uint256 token_sold
        ) public 
        view
        returns (uint256) 
    {
        require(token_sold > 0, "token_sold can't be zero");
        uint256 token_reserve = token.balanceOf(address(this));
        return getInputPrice(token_sold, token_reserve, address(this).balance);
    }

    function getTokenToEthOutputPirce(
        uint256 eth_bought
        ) public 
        view
        returns (uint256) 
    {
        require(eth_bought > 0, "token_sold can't be zero");
        uint256 token_reserve = token.balanceOf(address(this));
        return getOutputPrice(eth_bought, token_reserve, address(this).balance);
    }

    function factoryAddress() public view returns (address) {
        return address(factory);
    }

    function tokenAddress() public view returns (address) {
        return address(token);
    }
}