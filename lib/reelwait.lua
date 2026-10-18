-- reelwait: hitung reels yang ditonton (stats) + countdown mode limit.
-- ponytail: dijalankan mpv sendiri, jadi tidak perlu proses observer IPC terpisah.
local opts = { count = "", ["until"] = "", row = "" }
require("mp.options").read_options(opts, "reelwait")

local n = 0
mp.register_event("file-loaded", function()
  n = n + 1
  local f = opts.count ~= "" and io.open(opts.count, "w")
  if f then
    f:write(n)
    f:close()
  end
end)

-- row diisi player.sh hanya untuk tct (tanpa OSD): tulis ke baris terminal yang disisakan.
local row = tonumber(opts.row)
local function show(text)
  if not row then
    mp.osd_message(text, 2)
    return
  end
  io.stdout:write(string.format("\27[%d;1H\27[0m\27[2K %s", row, text))
  io.stdout:flush()
end

local stop_at = tonumber(opts["until"])
if stop_at then
  mp.add_periodic_timer(1, function()
    local left = stop_at - os.time()
    if left <= 0 then
      mp.command("quit")
      return
    end
    show(string.format("limit %d:%02d lagi", math.floor(left / 60), left % 60))
  end)
end

-- Scroll trackpad/mouse = swipe. Satu gesture mengirim puluhan event wheel, jadi hanya event
-- pertama setelah jeda 0.4 detik yang dihitung: satu gesture = satu video.
local last_wheel = 0
local function swipe(cmd)
  return function()
    local now = mp.get_time()
    if now - last_wheel >= 0.4 then mp.command(cmd) end
    last_wheel = now
  end
end
mp.add_key_binding(nil, "next", swipe("playlist-next"))
mp.add_key_binding(nil, "prev", swipe("playlist-prev"))
