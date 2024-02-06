pragma solidity ^0.8.19;

interface Builder {
    struct Config {
        uint256 chainId;
    }
    struct Bundle {
        uint256 height;
        bytes transaction;
        uint256 profit;
    }
    struct SimResult {
        uint256 profit;
    }
    struct Block {
        uint256 profit;
    }

    function newSession() external returns (string memory sessionId);
    function addTransaction(string memory sessionId, bytes memory tx) external returns (SimResult memory);

    function simulate(Bundle memory bundle) external returns (SimResult memory);
    function buildBlock(Bundle[] memory bundle) external returns (Block memory);
}

contract WithBuilder {
    Builder.Config config; // onchain!

    constructor(uint256 chainId) {
        config = Builder.Config(chainId);
    }

    function builder() internal returns (Builder) {
        (bool ok, bytes memory data) = SM_ADDR.staticcall(abi.encodeWithSelector(SM.getService.selector, "builder", abi.encode(config)));
        require(ok, string(abi.encodePacked("getService for builder failed: ", string(data))));
        (bytes32 handle, bytes memory err) = abi.decode(data, (bytes32, bytes));
        require(err.length == 0, string(abi.encodePacked("could not initialize builder: ", string(err))));
        return Builder(address(new ExternalService(handle)));
    }
}

interface Redis {
    // Internally keys and pubsub can be different instances!
    function set(string memory key, bytes memory value) external;
    function get(string memory key) external returns (bytes memory);
    function publish(string memory topic, bytes memory msg) external;
    function get_message(string memory topic, address subscriber) external returns (bytes memory);

    function subscribe(string memory topic, address subscriber) external;
    function unsubscribe(string memory topic, address subscriber) external;
}

interface RedisSubscriber {
    function onRedisMessage(string memory topic, bytes memory msg) external;
}

contract WithRedis {
    address _volatile_redis; /* volatile, dropped after execution */
    function redis() internal returns (Redis) {
        if (_volatile_redis == address(0x0)) {
            (bool ok, bytes memory data) = SM_ADDR.staticcall(abi.encodeWithSelector(SM.getService.selector, "redis", bytes("")));
            require(ok, string(abi.encodePacked("getService for redis failed: ", string(data))));
            (bytes32 handle, bytes memory err) = abi.decode(data, (bytes32, bytes));
            require(err.length == 0, string(abi.encodePacked("could not initialize redis: ", string(err))));
            _volatile_redis = address(new ExternalService(handle));
        }
        return Redis(_volatile_redis);
    }
}

/* Decorator adding handle to precompile calls */
contract ExternalService {
    bytes32 handle;
    constructor(bytes32 _handle) {
        handle = _handle;
    }

    fallback(bytes calldata cdata) external returns (bytes memory) {
        (bool ok, bytes memory data) = SM_ADDR.staticcall(abi.encodeWithSelector(SM.callService.selector, handle, cdata));
        require(ok, string(abi.encodePacked("service call failed: ", string(data))));
        return data;
    }
}

address constant SM_ADDR = address(0x3507);

interface SM {
    function getService(string memory service_name, bytes memory config) external returns (bytes32 handle, bytes memory err);
    function callService(bytes32 handle, bytes memory cdata) external returns (bytes memory);
}
