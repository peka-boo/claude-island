//
//  test_lru_cache_regression.swift
//  Regression test: LRUCache<String, V> get/set must not recurse infinitely.
//  Crash case: EXC_BAD_ACCESS (stack overflow) in LRUCache.get via
//  ConversationParser.parse → SessionStore.processFileUpdate.
//

import Foundation

func assertLRU(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct LRUCacheRegressionTestRunner {
    static func main() {
        let cache = LRUCache<String, Int>(capacity: 2)

        // set then get on a String key — this used to stack-overflow
        cache.set("session-a", value: 1)
        cache.set("session-b", value: 2)

        assertLRU(cache.get("session-a") == 1, "get should return the stored value")
        assertLRU(cache.get("missing") == nil, "get on absent key should return nil")

        // eviction still works
        cache.set("session-c", value: 3)
        assertLRU(cache.get("session-b") == nil, "LRU eviction should drop the least recently used key")
        assertLRU(cache.get("session-c") == 3, "newest key should survive eviction")

        print("LRUCache regression checks passed")
    }
}
