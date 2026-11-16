#pragma once
#include <Arduino.h>


// ---- bell_core.h ----
#include <stdint.h>
#include <stddef.h>
#include <string.h>

namespace bell {
constexpr int MAX_TIMES = 20;
constexpr int32_t OFFSET = 19800; // IST, no DST
constexpr uint32_t MIN_EPOCH = 1704067200; // 2024-01-01 UTC
constexpr uint32_t HOLDOVER_MS = 24UL * 60 * 60 * 1000;
constexpr uint32_t PULSE_MS = 5000;
constexpr uint32_t GAP_MS = 10000; // minimum gap after a complete pulse
constexpr uint32_t GRACE_SEC = 15;
inline uint32_t elapsed(uint32_t now, uint32_t then) { return now - then; }

struct Schedule {
  uint16_t times[MAX_TIMES] = {};
  uint8_t count = 0;
  uint8_t days = 0x7f; // bit 0 Sunday; all days preserves original behavior
  char mode[33] = {};
};
inline bool valid(const Schedule& s) {
  if (s.count > MAX_TIMES || s.days > 127 || !s.mode[0] || s.mode[32]) return false;
  // Firebase key restrictions, preserving spaces and UTF-8 mode names.
  for (const unsigned char* p=reinterpret_cast<const unsigned char*>(s.mode); *p; ++p)
    if (*p<32 || *p==127 || strchr(".#$[]/",*p)) return false;
  for (int i=0;i<s.count;++i)
    if (s.times[i]>1439 || (i && s.times[i]<=s.times[i-1])) return false;
  return true;
}
struct State {
  Schedule schedule{};
  uint32_t lastScheduled = 0; // UTC epoch minute, retained for this boot only
  uint32_t lastManual = 0;    // increasing command sequence, retained for this boot only
};
struct Store {
  virtual bool save(const State&) = 0;
  virtual ~Store() = default;
};
struct Command { uint32_t seq, issuedAt, expiresAt; };
enum class Result { None, Scheduled, Manual, Invalid, StorageFault, Busy, Late, ClockReset };

class Engine {
 public:
  State state;
  bool fault = false;
  bool schedulePaused = false;
  explicit Engine(Store& s, const State& initial = State{}) : state(initial), store(s) {}
  void synced(uint32_t ms) { synchronized=true; syncMs=ms; }
  bool clockOK(uint32_t utc, uint32_t ms) const {
    return synchronized && utc>=MIN_EPOCH && elapsed(ms,syncMs)<=HOLDOVER_MS;
  }
  bool configure(const Schedule& s) {
    if (fault || !valid(s)) return false;
    if (state.schedule.count==s.count && state.schedule.days==s.days &&
        strcmp(state.schedule.mode,s.mode)==0 &&
        memcmp(state.schedule.times,s.times,s.count*sizeof(uint16_t))==0) return true;
    State next=state; next.schedule=s;
    if (!store.save(next)) { fault=true; return false; }
    state=next; armed=false; // never ring retrospectively when configuration changes
    return true;
  }
  Result tick(uint32_t utc, uint32_t ms) {
    if (synchronized && elapsed(ms,syncMs)>HOLDOVER_MS) synchronized=false;
    if (fault || schedulePaused || !clockOK(utc,ms)) { armed=false; return Result::None; }
    uint32_t minute=utc/60;
    if (!armed) { arm(utc,ms); return Result::None; }
    int64_t drift=int64_t(utc)-previousUtc-int64_t(elapsed(ms,previousMs)/1000);
    previousUtc=utc; previousMs=ms;
    if (drift>2 || drift< -2) { seenMinute=minute; return Result::ClockReset; }
    if (minute==seenMinute) return Result::None;
    seenMinute=minute;
    if (!due(utc) || minute<=state.lastScheduled) return Result::None;
    if (utc%60>GRACE_SEC) return Result::Late;
    if (!available(ms)) return Result::Busy;
    State next=state; next.lastScheduled=minute;
    if (!store.save(next)) { fault=true; return Result::StorageFault; }
    state=next; fired=true; firedMs=ms;
    return Result::Scheduled;
  }
  Result manual(const Command& cmd, uint32_t utc, uint32_t ms) {
    if (fault || !clockOK(utc,ms) || !armed || !cmd.seq || cmd.seq<=state.lastManual ||
        cmd.issuedAt>utc || cmd.expiresAt<=utc || cmd.expiresAt<=cmd.issuedAt ||
        cmd.expiresAt-cmd.issuedAt>30 || utc-cmd.issuedAt>30) return Result::Invalid;
    // Consume even when busy: a command cannot unexpectedly ring later.
    State next=state; next.lastManual=cmd.seq;
    if (!store.save(next)) { fault=true; return Result::StorageFault; }
    state=next;
    if (!available(ms) || nearScheduled(utc)) return Result::Busy;
    fired=true; firedMs=ms;
    return Result::Manual;
  }
  // Only call after a fresh streamed false->true edge has been acknowledged
  // false on the server. The boolean protocol cannot identify distinct queued clicks.
  Result legacyButton(uint32_t utc,uint32_t ms) {
    if(fault || !clockOK(utc,ms)) return Result::Invalid;
    if(!available(ms) || (!schedulePaused && nearScheduled(utc))) return Result::Busy;
    fired=true; firedMs=ms; return Result::Manual;
  }
  uint32_t syncAge(uint32_t ms) const { return synchronized ? elapsed(ms,syncMs) : UINT32_MAX; }
  uint32_t nextEvent(uint32_t utc) const {
    if(!state.schedule.count || !state.schedule.days) return 0;
    uint32_t localDay=(utc+OFFSET)/86400;
    for(unsigned d=0;d<8;++d) {
      uint32_t day=localDay+d;
      if(!(state.schedule.days & (1u<<((day+4)%7)))) continue;
      for(unsigned i=0;i<state.schedule.count;++i) {
        uint32_t candidate=day*86400+state.schedule.times[i]*60-OFFSET;
        if(candidate>utc && candidate/60>state.lastScheduled) return candidate;
      }
    }
    return 0;
  }
  bool nearScheduled(uint32_t utc) const {
    for (int d=-int(GRACE_SEC);d<=10;++d)
      if ((utc+d)%60==0 && due(utc+d)) return true;
    return false;
  }
 private:
  Store& store;
  bool synchronized=false, armed=false, fired=false;
  uint32_t syncMs=0, seenMinute=0, previousUtc=0, previousMs=0, firedMs=0;
  void arm(uint32_t utc,uint32_t ms) { armed=true; seenMinute=utc/60; previousUtc=utc; previousMs=ms; }
  bool available(uint32_t ms) const { return !fired || elapsed(ms,firedMs)>=PULSE_MS+GAP_MS; }
  bool due(uint32_t utc) const {
    uint32_t local=utc+OFFSET;
    unsigned weekday=(local/86400+4)%7;
    if (!(state.schedule.days & (1u<<weekday))) return false;
    unsigned minute=(local%86400)/60;
    for (int i=0;i<state.schedule.count;++i) if (state.schedule.times[i]==minute) return true;
    return false;
  }
};
} // namespace bell

// ---- config_parse.h ----
#include <ArduinoJson.h>
namespace bell {
inline bool parseSchedule(const char* json,const char* mode,Schedule& output) {
  if(!mode || strlen(mode)>32) return false;
  Schedule candidate{}; strcpy(candidate.mode,mode);
  if(!valid(candidate)) return false;
  DynamicJsonDocument doc(2048);
  if(deserializeJson(doc,json)) return false;
  JsonVariant times=doc["times"];
  if(doc.containsKey("daysMask")) {
    if(!doc["daysMask"].is<unsigned>() || doc["daysMask"].as<unsigned>()>127) return false;
    candidate.days=doc["daysMask"].as<unsigned>();
  }
  // RTDB removes empty arrays. An explicit zero day mask can safely disable
  // a schedule even when /times is missing; missing active times is an error.
  if(candidate.days==0 && times.isNull()) { output=candidate; return true; }
  if(!times.is<JsonArray>() || times.size()>MAX_TIMES) return false;
  for(JsonVariant value:times.as<JsonArray>()) {
    if(!value.is<int>() || value.as<int>()<0 || value.as<int>()>1439) return false;
    unsigned minute=value.as<unsigned>();
    int pos=0; while(pos<candidate.count && candidate.times[pos]<minute) ++pos;
    if(pos<candidate.count && candidate.times[pos]==minute) continue;
    for(int j=candidate.count;j>pos;--j) candidate.times[j]=candidate.times[j-1];
    candidate.times[pos]=minute; ++candidate.count;
  }
  if(!valid(candidate)) return false;
  output=candidate; return true;
}
inline bool parseCommand(const char* json,Command& output) {
  StaticJsonDocument<256> doc;
  if(deserializeJson(doc,json)) return false;
  if(!doc["seq"].is<uint32_t>() || !doc["issuedAt"].is<uint32_t>() || !doc["expiresAt"].is<uint32_t>()) return false;
  output={doc["seq"],doc["issuedAt"],doc["expiresAt"]}; return true;
}
}


// ---- live_feed.h ----
#include <ArduinoJson.h>
namespace bell {
// Boolean poll state. Inputs are small synthetic snapshots/events, not department JSON.
// Root PUT is a new baseline (including Firebase's automatic reconnect snapshot).
class LiveFeed {
 public:
  bool baseline=false, configDirty=true, configUnconfirmed=false, pending=false, cleanup=false;
  uint32_t revision=0, receivedMs=0;
  static constexpr uint32_t REQUEST_TTL_MS=5000;
  void disconnect() {
    baseline=false; pending=false; cleanup=false; known=false; lastValue=false;
    configDirty=true; configUnconfirmed=false; ++revision;
  }
  bool apply(const char* event,const char* path,const char* json,uint32_t ms) {
    bool put=!strcmp(event,"put"), patch=!strcmp(event,"patch");
    if(!put && !patch) { disconnect(); return false; }
    if(!path || path[0]!='/' || strlen(path)>160 || !json || strlen(json)>4096) { disconnect(); return false; }
    DynamicJsonDocument doc(256);
    if(deserializeJson(doc,json)) { disconnect(); return false; }
    if(put && !strcmp(path,"/")) {
      if(!doc.is<JsonObject>() && !doc.isNull()) { disconnect(); return false; }
      baseline=true; pending=false; known=false; lastValue=false; cleanup=false;
      JsonVariant v=doc["manualRing"];
      if(v.isNull()) { known=true; }
      else if(v.is<bool>()) { known=true; lastValue=v.as<bool>(); cleanup=lastValue; }
      configDirty=true; configUnconfirmed=true; ++revision;
      return true; // NEVER treat baseline true as a fresh click
    }
    if(!baseline) return false;
    if(patch && !doc.is<JsonObject>()) { disconnect(); return false; }
    if(!strcmp(path,"/")) { // root PATCH may contain Firebase multi-location paths
      for(JsonPair entry:doc.as<JsonObject>()) {
        const char* key=entry.key().c_str();
        if(!strcmp(key,"manualRing")) observe(entry.value(),ms);
        if(configKey(key)) { configDirty=true; configUnconfirmed=true; ++revision; }
      }
    } else {
      if(put && !strcmp(path,"/manualRing")) observe(doc.as<JsonVariant>(),ms);
      if(configKey(path+1)) { configDirty=true; configUnconfirmed=true; ++revision; }
    }
    return true;
  }
  bool fresh(uint32_t ms) const { return baseline && pending && elapsed(ms,receivedMs)<=REQUEST_TTL_MS; }
  void consumed() { pending=false; cleanup=false; /* wait for server false event to re-arm */ }
  void abandon() { pending=false; cleanup=true; }
  void refreshed(uint32_t appliedRevision) { if(appliedRevision==revision) { configDirty=false; configUnconfirmed=false; } }
 private:
  bool known=false, lastValue=false;
  static bool configKey(const char* key) {
    return !strcmp(key,"mode") || !strcmp(key,"schedules") || !strncmp(key,"schedules/",10);
  }
  void observe(JsonVariant v,uint32_t ms) {
    if(!v.is<bool>() && !v.isNull()) { known=false; pending=false; return; }
    bool value=v.is<bool>() && v.as<bool>();
    if(value && known && !lastValue && !pending && !cleanup) { pending=true; receivedMs=ms; }
    if(!value) { pending=false; cleanup=false; }
    known=true; lastValue=value;
  }
};
}


// ---- button_transaction.h ----
namespace bell {
enum class ButtonAck { None, Ready, StaleCleared, Cancelled, ReadFailed, WriteFailed, Expired };
// Shared by firmware and fault-injection tests. Transport owns the ETag obtained
// by read(); clear() must conditionally write false using that same ETag.
template<class Transport,class Clock>
ButtonAck acknowledgeButton(LiveFeed& feed,Transport& transport,Clock clock) {
  bool requested=feed.fresh(clock());
  if(feed.pending && !requested) feed.abandon();
  if(!requested && !feed.cleanup) return ButtonAck::None;
  bool value=false;
  if(!transport.read(value)) { feed.abandon(); return ButtonAck::ReadFailed; }
  if(!value) { feed.consumed(); return ButtonAck::Cancelled; }
  if(!transport.clear()) { feed.abandon(); return ButtonAck::WriteFailed; }
  bool timely=feed.fresh(clock());
  feed.consumed();
  if(!requested) return ButtonAck::StaleCleared;
  return timely ? ButtonAck::Ready : ButtonAck::Expired;
}
}
