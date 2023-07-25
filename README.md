<p align="center">
  <img src="https://i.imgur.com/aeQoOZ0.png">
</p>

## 🌙 Moonlite

Moonlite is a work-in-progress (WIP), lightweight in-game player for sequences created in Moon Animator, a tool developed by xSIXx. This project is actively developed and maintained by MaximumADHD.

## 🔖 Current Version
- 0.6.0

---

## 🚀 API Documentation 

### 🌑 Moonlite

#### CreatePlayer
```lua
Moonlite.CreatePlayer(save: StringValue) -> MoonliteTrack
```
Loads the provided MoonAnimator save to be played back.

### 🌖 MoonliteTrack
```lua
type MoonliteTrack = Moonlite.Track
```
MoonliteTrack is a type exported from the module that represents a playback track.

#### Play
```lua
MoonliteTrack:Play() -> ()
```
Starts playing the track's elements.<br/>
Has no effect if already playing.

#### Stop
```lua
MoonliteTrack:Stop() -> ()
```
Stops all playing track elements.

#### Reset
```lua
MoonliteTrack:Reset() -> ()
```
Resets any modified properties to their declared defaults.<br/>
Note: Calling this while a track is playing is undefined behavior.

#### IsPlaying
```lua
MoonliteTrack:IsPlaying() -> boolean
```
Returns true if the track still has elements playing.

#### Looped
```lua
MoonliteTrack.Looped: boolean
```
Whether the track playback will loop on completion.

#### Completed
```lua
MoonliteTrack.Completed: RBXScriptSignal
```
Fired when playback of the track is completed.