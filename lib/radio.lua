-- Plasmarchy radio for mpv: when only a few songs are left in the queue, append songs similar to the one
-- that plays now (YouTube Music's "Up next"), so the radio never runs out.
local helper = debug.getinfo(1, "S").source:match("^@(.*/)") .. "music.py"
local busy = false

mp.register_event("file-loaded", function()
    local pos = mp.get_property_number("playlist-pos", 0)
    local count = mp.get_property_number("playlist-count", 0)
    if busy or count - pos > 5 then return end
    local id = mp.get_property("path", ""):match("[?&]v=([%w_-]+)")
    if not id then return end
    busy = true
    mp.command_native_async({ name = "subprocess", args = { "python3", "-I", helper, "yt-extend", id },
                              playback_only = false }, function() busy = false end)
end)
