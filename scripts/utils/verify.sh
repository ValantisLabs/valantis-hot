# Chainlink Feed Verification Script
# forge verify-contract \
#     --chain-id 100 \
#     --num-of-optimizations 20000 \
#     --watch \
#     --constructor-args $(cast abi-encode "constructor(uint8)" 8 ) \
#     --etherscan-api-key G3C7HAXCHCSQDDIWPAHQSTE4MNFEUEUPKF \
#     --compiler-version v0.8.19 \
#     0xA2BFa9dD4D2787Ea350Fe7325A92AAd4c1E592D2 \
#     test/mocks/MockChainlinkOracle.sol:MockChainlinkOracle

# MockToken Verify Script
# forge verify-contract \
#     --chain-id 100 \
#     --num-of-optimizations 20000 \
#     --watch \
#     --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin" "USDC" 6 ) \
#     --etherscan-api-key G3C7HAXCHCSQDDIWPAHQSTE4MNFEUEUPKF \
#     --compiler-version v0.8.19 \
#     0x64efc365149C78C55bfccaB24A48Ae03AffCa572 \
#     test/mocks/MockToken.sol:MockToken

# SOT Verify Script
forge verify-contract \
    --chain-id 100 \
    --num-of-optimizations 20000 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,uint160,uint160,uint160,uint32,uint32,uint32,uint16,uint16,uint16,uint16,uint16)" 0xF636790d517D2fD5277A869891B78D1bFAcB96f5 0xeED403D7cacFC3c228b816B87C7a97513f782F01 0xeED403D7cacFC3c228b816B87C7a97513f782F01 0x031C37cBc3427011f949513483341f84D5F1e425 0xA2BFa9dD4D2787Ea350Fe7325A92AAd4c1E592D2 0x573effB45DD0c711Cd18f81817082afF9e3FCA59 3799649193200520362794529325056 3068493539683605223466464182272 3961408125713216879677197516800 1200 3600 3600 200 50 100 10000 1) \
    --etherscan-api-key G3C7HAXCHCSQDDIWPAHQSTE4MNFEUEUPKF \
    --compiler-version v0.8.19 \
    0xffb666fE4C401Af7FbdE1C7b675f379dfF34997D \
    src/SOT.sol:SOT 
