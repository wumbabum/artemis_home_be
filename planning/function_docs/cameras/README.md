# Cameras

## Status: Future — deferred, not in v1

## Concept
Camera feeds for monitoring. Explicitly deferred — no live streaming in v1. This is the most complex device type due to video streaming requirements.

## HA Integration (expected)
- HA domain: `camera`
- Services: `camera.snapshot`, `camera.turn_on`, `camera.turn_off`
- Streams: RTSP, MJPEG, or HLS depending on camera
- HA can proxy camera streams via `/api/camera_proxy_stream/<entity_id>`

### Expected State Shape
```json
{
  "entity_id": "camera.front_porch",
  "state": "idle",
  "attributes": {
    "friendly_name": "Front Porch Camera",
    "brand": "TBD",
    "model_name": "TBD",
    "frontend_stream_type": "hls"
  }
}
```

## Artemis Features (planned, future)
- Camera tab on dashboard
- Snapshot view: latest still image per camera
- Live stream: embed HLS or WebRTC stream in the UI
- Motion alerts: push notification when motion detected
- Recording playback (if NVR is set up)
- Guest access: temporary camera view for delivery drivers

## Complexity Notes
- Live streaming adds significant complexity:
  - RTSP → WebRTC or HLS transcoding
  - Bandwidth considerations for remote viewing
  - HA's camera proxy may be sufficient for LAN, but not for remote access through Tailscale
- Consider using HA's built-in stream integration or Frigate NVR
- Camera feeds are bandwidth-heavy — may need separate streaming path from the API

## Device Config Schema (JSONB, planned)
```json
{
  "manufacturer": "TBD",
  "protocol": "rtsp or onvif",
  "stream_url": "rtsp://...",
  "supports_ptz": false,
  "supports_motion_detection": true
}
```

## Open Questions
- Which cameras to purchase (PoE? WiFi?)
- Whether to use Frigate for NVR/motion detection
- How to handle remote streaming through Tailscale (bandwidth, latency)
- Whether snapshots-only is sufficient for v2 before adding live streaming in v3
