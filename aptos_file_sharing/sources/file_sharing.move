module file_sharing::file_sharing {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::event;
    use std::vector;

    // Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_FILE_NOT_FOUND: u64 = 2;

    struct FileInfo has store, drop {
        file_hash: string::String,
        file_name: string::String,
        owner: address,
        shared_with: vector<address>,
        timestamp: u64
    }

    struct FileStorage has key {
        files: vector<FileInfo>,
        file_count: u64
    }

    struct FileEvent has drop, store {
        file_hash: string::String,
        owner: address,
        action: string::String
    }

    struct EventHandle has key {
        file_events: event::EventHandle<FileEvent>,
    }

    public fun init_storage(account: &signer) {
        if (!exists<FileStorage>(signer::address_of(account))) {
            move_to(account, FileStorage {
                files: vector::empty(),
                file_count: 0
            });
            move_to(account, EventHandle {
                file_events: account::new_event_handle<FileEvent>(account),
            });
        }
    }

    public entry fun upload_file(
        account: &signer,
        file_hash: string::String,
        file_name: string::String
    ) acquires FileStorage, EventHandle {
        let sender = signer::address_of(account);
        if (!exists<FileStorage>(sender)) {
            init_storage(account);
        };
        let storage = borrow_global_mut<FileStorage>(sender);
        let file_info = FileInfo {
            file_hash,
            file_name,
            owner: sender,
            shared_with: vector::empty(),
            timestamp: aptos_framework::timestamp::now_microseconds()
        };
        vector::push_back(&mut storage.files, file_info);
        storage.file_count = storage.file_count + 1;
        // Emit event
        let event_handle = borrow_global_mut<EventHandle>(sender);
        event::emit_event(&mut event_handle.file_events, FileEvent {
            file_hash,
            owner: sender,
            action: string::utf8(b"upload")
        })
    }

    public entry fun share_file(
        account: &signer,
        file_hash: string::String,
        shared_with_address: address
    ) acquires FileStorage {
        let sender = signer::address_of(account);
        let storage = borrow_global_mut<FileStorage>(sender);
        let i = 0;
        let len = vector::length(&storage.files);
        while (i < len) {
            let file = vector::borrow_mut(&mut storage.files, i);
            if (file.file_hash == file_hash) {
                if (file.owner == sender) {
                    vector::push_back(&mut file.shared_with, shared_with_address);
                    break;
                } else {
                    abort E_NOT_AUTHORIZED;
                };
            };
            i = i + 1;
        };
    }

    public fun get_file_count(addr: address): u64 acquires FileStorage {
        if (!exists<FileStorage>(addr)) {
            return 0;
        };
        let storage = borrow_global<FileStorage>(addr);
        storage.file_count
    }
}
