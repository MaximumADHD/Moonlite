<p align="center">
  <img src="https://i.imgur.com/aeQoOZ0.png">
</p>

## 🌙 Moonlite

Moonlite is a work-in-progress (WIP), lightweight in-game player for sequences created in Moon Animator, a tool developed by xSIXx. This project is actively developed and maintained by MaximumADHD.

## 🔖 Current Version
- 0.5.0

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
Starts playing the track's elements.

#### Stop
```lua
MoonliteTrack:Stop() -> ()
```
Stops all playing track elements.

#### Reset
```lua
MoonliteTrack:Reset() -> ()
```
Resets any modified properties to their declared defaults. Note: Calling this while a track is playing is undefined behavior.

#### IsPlaying
```lua
MoonliteTrack:IsPlaying() -> boolean
```
Returns true if the track still has elements playing.

#### Info
```lua
MoonliteTrack.Info: MoonliteInfo
```
A dictionary of metadata about the MoonAnimator save.

#### Completed
```lua
MoonliteTrack.Completed: RBXScriptSignal
```
Fired when playback of the track is completed.

### 🌒 MoonliteInfo

#### Created
```lua
MoonliteInfo.Created: number
```
UNIX Timestamp of when the animation was created.

#### ExportedPriority
```lua
MoonliteInfo.ExportedPriority: string
```
Maps to Enum.AnimationPriority, intended priority for this animation if it was created for a joint rig.

#### Modified
```lua
MoonliteInfo.Modified: number
```
UNIX Timestamp of when the animation was last modified.

#### Length
```lua
MoonliteInfo.Length: number
```
Expected duration of this track's playback.

#### Looped
```lua
MoonliteInfo.Looped: number
```
Whether the playback of this track should be looped. Currently has no effect, but may in the future.
