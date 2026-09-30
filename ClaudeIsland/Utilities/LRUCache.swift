//
//  LRUCache.swift
//  ClaudeIsland
//
//  Thread-safe Least Recently Used (LRU) cache with configurable maximum capacity.
//

import Foundation

/// A thread-safe LRU cache that automatically evicts least recently used items when capacity is reached.
final class LRUCache<Key: Hashable, Value>: @unchecked Sendable {
    private let capacity: Int
    private var cache: [Key: Node<Key, Value>] = [:]
    private var head: Node<Key, Value>?
    private var tail: Node<Key, Value>?
    private let lock = NSLock()
    
    /// The number of currently cached items.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
    
    /// Creates a new LRU cache with the given maximum capacity.
    /// - Parameter capacity: The maximum number of items the cache can hold. Must be > 0.
    init(capacity: Int) {
        precondition(capacity > 0, "LRUCache capacity must be greater than zero")
        self.capacity = capacity
    }
    
    /// Returns the value for the given key, if present.
    /// Accessing a value marks it as recently used.
    func get(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let node = cache[key] else { return nil }
        // Move to front (most recently used)
        moveToHead(node)
        return node.value
    }
    
    /// Sets the value for the given key.
    /// If the key already exists, its value is updated and marked as recently used.
    /// If the cache is at capacity, the least recently used item is evicted.
    func set(_ key: Key, value: Value) {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingNode = cache[key] {
            // Update existing node
            existingNode.value = value
            moveToHead(existingNode)
        } else {
            // Create new node
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToHead(newNode)
            
            // Evict if necessary
            if cache.count > capacity {
                evictTail()
            }
        }
    }
    
    /// Removes the value for the given key, if present.
    @discardableResult
    func remove(_ key: Key) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        
        guard let node = cache[key] else { return nil }
        removeNode(node)
        cache.removeValue(forKey: key)
        return node.value
    }
    
    /// Removes all items from the cache.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        
        cache.removeAll()
        head = nil
        tail = nil
    }
    
    /// Returns all keys currently in the cache.
    func allKeys() -> [Key] {
        lock.lock()
        defer { lock.unlock() }
        
        return Array(cache.keys)
    }
    
    /// Returns all values currently in the cache.
    func allValues() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        
        return cache.values.map { $0.value }
    }
    
    // MARK: - Private methods
    
    private func addToHead(_ node: Node<Key, Value>) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node
        if tail == nil {
            tail = node
        }
    }
    
    private func removeNode(_ node: Node<Key, Value>) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        
        if node === head {
            head = node.next
        }
        if node === tail {
            tail = node.prev
        }
    }
    
    private func moveToHead(_ node: Node<Key, Value>) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }
    
    private func evictTail() {
        guard let tailNode = tail else { return }
        removeNode(tailNode)
        cache.removeValue(forKey: tailNode.key)
    }
}

// MARK: - Node

extension LRUCache {
    private class Node<Key: Hashable, Value> {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }
}