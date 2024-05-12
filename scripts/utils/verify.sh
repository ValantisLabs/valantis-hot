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

# SovereignPool Verify Script
# forge verify-contract \
#     --chain-id 100 \
#     --num-of-optimizations 20000 \
#     --watch \
#     --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,bool,bool,uint256,uint256,uint256)" 0x64efc365149C78C55bfccaB24A48Ae03AffCa572 0x682d49D0Ead2B178DE4125781d2CEd108bEe41fD 0x25C15143f746A3d0722b4013aeDd90480e628740 0xeED403D7cacFC3c228b816B87C7a97513f782F01 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000 false false 0 0 0) \
#     --etherscan-api-key G3C7HAXCHCSQDDIWPAHQSTE4MNFEUEUPKF \
#     --compiler-version v0.8.19 \
#     0xCe626E0177b26066aF77f413Bf343F5BcABd682a \
#     lib/valantis-core/src/pools/SovereignPool.sol:SovereignPool 

    
# HOT Verify Script
forge verify-contract \
    --chain-id 100 \
    --num-of-optimizations 20000 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address,address,address,uint160,uint160,uint160,uint32,uint32,uint32,uint16,uint16,uint16,uint16,uint16)" 0xF18b966Ad80eC4a866a7E795Cb1a0D5fdF59DC66 0xeED403D7cacFC3c228b816B87C7a97513f782F01 0xeED403D7cacFC3c228b816B87C7a97513f782F01 0xC6C9b4C1616Ff870622aEbbdD998cA5973e01336 0x26C31ac71010aF62E6B486D1132E266D6298857D 0xa767f745331D267c7751297D982b050c93985627 1314917972337811703078981570920448 1252707241875239655932069007848031 1771595571142957102961017161607260 1200 86400 86400 1000 10000 1 10000 1) \
    --etherscan-api-key G3C7HAXCHCSQDDIWPAHQSTE4MNFEUEUPKF \
    --compiler-version v0.8.19 \
    0x8d5817dba8dafdc57ef7a2fc22b845f28d496c61 \
    src/HOT.sol:HOT 


