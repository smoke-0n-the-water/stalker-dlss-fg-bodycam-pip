#pragma once
#include <atomic>
#include <map>
#include <memory>
#include <mutex>
#include <vector>

// Only the control/render thread retires owners. Worker closures contain no
// owning texture reference, even after publishing completion.
namespace TextureLoadLifetime {
template<class Owner> class Queue {
    struct Record {
        Owner owner;
        std::atomic<bool> complete{false};
        explicit Record(const Owner& value):owner(value){}
    };
    std::mutex mutex_;
    std::map<const void*,std::unique_ptr<Record>> pending_;
    bool closed_=false;
public:
    template<class Schedule,class Load>
    bool Submit(const Owner& owner,const void* key,Schedule schedule,Load load) {
        std::lock_guard<std::mutex> lock(mutex_);
        if(closed_ || pending_.find(key)!=pending_.end())return false;
        auto record=std::make_unique<Record>(owner);
        auto* raw=record.get();
        pending_.emplace(key,std::move(record));
        // Schedule while admission is locked so Close cannot miss an accepted
        // but not yet submitted task. The worker never takes this mutex.
        try { schedule([raw,load] {
            try { load(raw->owner); }
            catch(...) { raw->complete.store(true,std::memory_order_release);throw; }
            raw->complete.store(true,std::memory_order_release);
            // No record access after completion: Collect may now destroy it.
        }); }
        catch(...) { raw->complete.store(true,std::memory_order_release);throw; }
        return true;
    }
    void Collect() {
        std::vector<std::unique_ptr<Record>> retired;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            for(auto it=pending_.begin();it!=pending_.end();) {
                if(it->second->complete.load(std::memory_order_acquire)) {
                    retired.push_back(std::move(it->second));it=pending_.erase(it);
                } else ++it;
            }
        }
        // Destructors may erase from the resource registry; neither mutex nor
        // a caller's registry iteration may surround this operation.
    }
    void Close() {std::lock_guard<std::mutex> lock(mutex_);closed_=true;}
};
}
