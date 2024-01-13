-- euclidean sample instrument
-- with trigger conditions.
--
-- ----------
--
-- based on tehn/playfair,
-- with generous contributions
-- from junklight and okyeron.
--
-- ----------
--
-- samples can be loaded
-- via the parameter menu.
--
-- ----------
-- home
--
-- enc1 = cycle through
--         the tracks.
-- enc2 = set the number
--         of trigs.
-- enc3 = set the number
--         of steps.
-- key2 = start and stop the
--         clock.
--
-- on the home screen,
-- key3 is alt.
--
-- alt + enc1 = mix volume
-- alt + enc2 = rotation
-- alt + enc3 = bpm
--
-- ----------
-- holding key1 will bring up the
-- track edit screen. release to
-- return home.
-- ----------
-- track edit
--
-- encoders 1-3 map to
-- parameters 1-3.
--
-- key2 = advance to the
--         next track.
-- key3 = advance to the
--         next page.
--
-- ----------
-- grid
-- ----------
--
-- col 1 select track edit
-- col 2 provides mute toggles
--
-- the dimly lit 5x5 grid is
-- made up of memory cells.
-- memory cells hold both
-- pattern and pset data.
-- simply pressing a cell
-- will load the pattern
-- data.
--
-- button 4 on row 7 starts
-- and stops the clock.
-- while the clock is stopped
-- the button will blink.
--
-- button 5 on row 7 is
-- the phase reset button.
--
-- button 8 on row 7 is
-- the pset load button.
--
-- to load a pset, press
-- and hold the pset load
-- button while touching
-- the desired memory cell.
--
-- open track edit pages
-- with grid buttons 4-7 on
-- the bottom row.
--
-- button 8 on the bottom row
-- is the copy button.
--
-- to copy a pattern to a new
-- cell hold the copy button,
-- and press the cell you'd
-- like to copy.
-- the cell will blink. while
-- still holding copy, press the
-- destination cell.
-- release the copy button.
--
-- v1.2 @justmat
--
-- llllllll.co/t/21081

er = require 'er'

engine.name = 'Ack'
local ack = require 'ack/lib/ack'
local MusicUtil = require "musicutil"

local g = grid.connect()
local midi_device = {}
local midi_device_names = {}

local alt = 0
local reset = false
-- 0 == home, 1 == track edit
local view = 0
local page = 0
local track_edit = 1
local stopped = 1
local pset_load_mode = false
local current_pset = 0

local midi_note_root = 60
local scale_notes = {}
local scale_names = {}

-- for new clock system
local clock_id = 0

function pulse()
  while true do
    clock.sync(1/4)
    step()
  end
end


function clock.transport.stop()
  clock.cancel(clock_id)
  reset_pattern()
end


function clock.transport.start()
  clock_id = clock.run(pulse)
end

-- a table of midi note on/off status i = 1/0
local note_off_queue = {}
for i = 1, 8 do
  note_off_queue[i] = 0
end

-- added for grid support - junklight
local current_mem_cell = 1
local current_mem_cell_x = 4
local current_mem_cell_y = 1
local copy_mode = false
local blink = false
local copy_source_x = -1
local copy_source_y = -1


function simplecopy(obj)
  if type(obj) ~= 'table' then return obj end
  local res = {}
  for k, v in pairs(obj) do
    res[simplecopy(k)] = simplecopy(v)
  end
  return res
end


local memory_cell = {}
for j = 1,25 do
  memory_cell[j] = {}
  for i=1, 8 do
    memory_cell[j][i] = {
      k = 0,
      n = 16,
      pos = 1,
      s = {},
      prob = 100,
      trig_logic = 0,
      logic_target = track_edit,
      rotation = 0,
      mute = 0
  }
  end
end


local function gettrack( cell , tracknum )
  return memory_cell[cell][tracknum]
end


local function cellfromgrid( x , y )
  return (((y - 1) * 5) + (x -4)) + 1
end


local function rotate_pattern(t, rot, n, r)
  -- rotate_pattern comes to us via okyeron and stackexchange
  n, r = n or #t, {}
  rot = rot % n
  for i = 1, rot do
    r[i] = t[n - rot + i]
  end
  for i = rot + 1, n do
    r[i] = t[i - rot]
  end
  return r
end


local function reer(i)
  if gettrack(current_mem_cell,i).k == 0 then
    for n=1,32 do gettrack(current_mem_cell,i).s[n] = false end
  else
    gettrack(current_mem_cell,i).s = rotate_pattern(er.gen(gettrack(current_mem_cell,i).k, gettrack(current_mem_cell,i).n), gettrack(current_mem_cell, i).rotation)
  end
end

local function send_midi_note_on(i,p)
  if params:get(i .. "_send_midi") == 2 then

    if params:get(i.."_use_scale") == 2 then
        if params:get(i.."_rnd_scale_note") == 2 then 
            p = math.random(p)
        end
        _note_playing = scale_notes[params:get(i.."_midi_scale")][p] - midi_note_root + params:get(i.."_midi_note")
        midi_device[params:get(i.."_midi_target")]:note_on(_note_playing, 100, params:get(i.."_midi_chan"))
        --print("note on | track:"..i.." | step:"..p.." | scale "..MusicUtil.SCALES[params:get(i.."_midi_scale")].name.." | root:"..params:get(i.."_midi_note").." | note:".._note_playing.." ["..MusicUtil.note_num_to_name(_note_playing, true).."]")
    else 
        midi_device[params:get(i.."_midi_target")]:note_on(params:get(i.."_midi_note"), 100, params:get(i.."_midi_chan"))
    end

    note_off_queue[i] = 1
  end
end

local function send_midi_note_off(i)
  if note_off_queue[i] == 1 then
    midi_device[params:get(i.."_midi_target")]:note_off(params:get(i.."_midi_note"), 100, params:get(i.."_midi_chan"))
    note_off_queue[i] = 0
  end
end

local function trig()
  -- mute state is ignored for trigger logics
  for i, t in ipairs(memory_cell[current_mem_cell]) do
    -- no trigger logic
    if t.trig_logic==0 and t.s[t.pos]  then
      if math.random(100) <= t.prob and t.mute == 0 then
        engine.trig(i-1)
        if i <= 4 and params:get(i .. "_send_crow") == 2 then
          crow.output[i]()
        end
        send_midi_note_on(i,t.pos)
      end
    else
      send_midi_note_off(i)
    end
    -- logical and
    if t.trig_logic == 1 then
      if t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos]  then
        if math.random(100) <= t.prob and t.mute == 0 then
          engine.trig(i-1)
          if i <= 4 and params:get(i .. "_send_crow") == 2 then
            crow.output[i]()
          end
          send_midi_note_on(i,t.pos)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical or
    elseif t.trig_logic == 2 then
      if t.s[t.pos] or gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        if math.random(100) <= t.prob and t.mute == 0 then
          engine.trig(i-1)
          if i <= 4 and params:get(i .. "_send_crow") == 2 then
            crow.output[i]()
          end
          send_midi_note_on(i,t.pos)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical nand
    elseif t.trig_logic == 3 then
      if t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos]  then
      elseif t.s[t.pos] then
        if math.random(100) <= t.prob and t.mute == 0 then
          engine.trig(i-1)
          if i <= 4 and params:get(i .. "_send_crow") == 2 then
            crow.output[i]()
          end
          send_midi_note_on(i,t.pos)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical nor
    elseif t.trig_logic == 4 then
      if not t.s[t.pos] and math.random(100) <= t.prob then
        if not gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] and t.mute == 0 then
          engine.trig(i-1)
          if i <= 4 and params:get(i .. "_send_crow") == 2 then
            crow.output[i]()
          end
          send_midi_note_on(i,t.pos)
        else break end
      else
        send_midi_note_off(i)
      end
    -- logical xor
    elseif t.trig_logic == 5 then
      if t.mute == 0 and math.random(100) <= t.prob then
        if not t.s[t.pos] and not gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        elseif t.s[t.pos] and gettrack(current_mem_cell,t.logic_target).s[gettrack(current_mem_cell,t.logic_target).pos] then
        else
          engine.trig(i-1)
          if i <= 4 and params:get(i .. "_send_crow") == 2 then
            crow.output[i]()
          end
          send_midi_note_on(i,t.pos)
          send_midi_note_off(i)
        end
      else break end
    end
  end
end

local function midi_note_formatter(param)
  note_number = param:get()
  note_name = MusicUtil.note_num_to_name(note_number, true)
  return note_number.." ["..note_name.."]"
end

function init()
  for i=1, 8 do reer(i) end

  for i = 1,#midi.vports do
    midi_device[i] = midi.connect(i)
    table.insert(midi_device_names, util.trim_string_to_width(midi_device[i].name,70))
  end

  for i = 1, #MusicUtil.SCALES do
    table.insert(scale_notes, MusicUtil.generate_scale_of_length(midi_note_root, i, 32))
    table.insert(scale_names, MusicUtil.SCALES[i].name)
  end

  screen.line_width(1)
  params:add_separator('tracks')
  for i = 1, 8 do
    params:add_group("track " .. i, 29)
    ack.add_channel_params(i)
    params:add_option(i.."_send_midi", i..": send midi", {"no", "yes"}, 1)
    params:add_option(i.."_midi_target", i..": device", midi_device_names, 1)
    params:add_number(i.."_midi_chan", i..": midi chan", 1, 16, 1)
    params:add_number(i.."_midi_note", i..": midi note", 0, 127, midi_note_root, midi_note_formatter)
    params:add_option(i.."_use_scale", i..": use scale", {"no", "yes"}, 1)
    params:add_option(i.."_midi_scale", i..": midi scale", scale_names, 1)
    params:add_option(i.."_rnd_scale_note", i..": randomize scale note", {"no", "yes"}, 1)
  end
  params:add_separator('crow sends')
  for i = 1, 8 do
    if i <= 4 then
      params:add_option(i .. "_send_crow", i .. ": send crow", {"no", "yes"}, 1)
    end
  end
  params:add_separator('effects')
  ack.add_effects_params()
  -- load default pset
  params:read()
  params:bang()
  -- load pattern data
  loadstate()

  if stopped==1 then
    clock.cancel(clock_id)
  else
    clock_id = clock.run(pulse)
  end
  
  -- grid refresh timer, 15 fps
  metro_grid_redraw = metro.init(function(stage) grid_redraw() end, 1 / 15)
  metro_grid_redraw:start()
  -- blink for copy mode
  metro_blink = metro.init(function(stage) blink = not blink end, 1 / 4)
  metro_blink:start()
  -- savestate timer
  metro_save = metro.init(function(stage) savestate() end, 10)
  metro_save:start()
  
  -- crow triggers
  for i = 1, 4 do
    crow.output[i].action = "pulse(.1, 5, 1)"
  end
end


function reset_pattern()
  reset = true
end


function step()
  if reset then
    for i=1,8 do
      gettrack(current_mem_cell,i).pos = 1
    end
    reset = false
  else
    for i=1,8 do
      gettrack(current_mem_cell,i).pos = (gettrack(current_mem_cell,i).pos % gettrack(current_mem_cell,i).n) + 1
    end
  end
  trig()
  redraw()
end


function key(n,z)
  -- home and track edit views
  if n==1 then view = z end
  -- track edit view
  if view==1 then
    if n==3 and z==1 then
      if params:get(track_edit.."_send_midi") == 1 then
        page = (page + 1) % 4
      -- there are only 2 pages of midi options
      else page = (page + 1) % 2 end
    end
  end
  if n==3 then alt = z end
  -- track selection in track edit view
  if view==1 then
    if n==2 and z==1 then
      track_edit = (track_edit % 8) + 1
    end
  end

  if alt==1 then
    -- track phase reset
    if n==2 and z==1 then
      if gettrack(current_mem_cell, track_edit).mute == 1 then
        gettrack(current_mem_cell, track_edit).mute = gettrack(current_mem_cell, track_edit).mute == 0 and 1 or 0
      else
        reset_pattern()
        if stopped == 1 then
            step()
        end
      end
    end
  end
  -- home view. start/stop
  if alt==0 and view==0 then
    if n==2 and z==1 then
      if stopped==0 then
        stopped = 1
        clock.cancel(clock_id)
      elseif stopped==1 then
        stopped = 0
        clock_id = clock.run(pulse)
      end
    end
  end
  redraw()
end


function enc(n,d)
  if alt==1 then
    -- mix volume control
    if n==1 then
      params:delta("output_level", d)
    -- track rotation control
    elseif n==2 then
      gettrack(current_mem_cell, track_edit).rotation = util.clamp(gettrack(current_mem_cell, track_edit).rotation + d, 0, 32)
      gettrack(current_mem_cell,track_edit).s = rotate_pattern( gettrack(current_mem_cell,track_edit).s, gettrack(current_mem_cell, track_edit).rotation )
      redraw()
    -- bpm control
    elseif n==3 then
      params:delta("clock_tempo", d)
    end
  -- track edit view
  elseif view==1  and page==0 then
    -- only show the engine edit options if midi note send is off
    if params:get(track_edit.."_send_midi") == 1 then
    -- per track volume control
      if n==1 then
        params:delta(track_edit .. "_vol", d)
      elseif n==2 then
        params:delta(track_edit .. "_vol_env_atk", d)
      elseif n==3 then
        params:delta(track_edit .. "_vol_env_rel", d)
      end
    -- if send midi is on
    else
      -- encoder 1 sets midi channel, 2 selects a note to send, 3 sets scale
      if n==1 then
        params:delta(track_edit .. "_midi_chan", d)
      elseif n==2 then
        params:delta(track_edit .. "_midi_note", d)
      elseif n==3 then
        params:delta(track_edit .. "_midi_scale", d)
      end
    end
  elseif view==1 and page==1 then
    -- trigger logic and probability settings
    if n==1 then
      gettrack(current_mem_cell,track_edit).trig_logic = util.clamp(d + gettrack(current_mem_cell,track_edit).trig_logic, 0, 5)
    elseif n==2 then
      gettrack(current_mem_cell,track_edit).logic_target = util.clamp(d+ gettrack(current_mem_cell,track_edit).logic_target, 1, 8)
    elseif n==3 then
      gettrack(current_mem_cell,track_edit).prob = util.clamp(d + gettrack(current_mem_cell,track_edit).prob, 1, 100)
    end

  elseif view==1 and page==2 then
    -- sample playback settings
    if n==1 then
      params:delta(track_edit .. "_speed", d)
    elseif n==2 then
      params:delta(track_edit .. "_start_pos", d)
    elseif n==3 then
      params:delta(track_edit .. "_end_pos", d)
    end

  elseif view==1 and page==3 then
    -- filter and fx sends
    if n==1 then
      params:delta(track_edit .. "_filter_cutoff", d)
    elseif n==2 then
      params:delta(track_edit .. "_delay_send", d)
    elseif n==3 then
      params:delta(track_edit .. "_reverb_send", d)
    end
  -- HOME
  -- choose focused track, track fill, and track length
  elseif n==1 and d==1 then
    track_edit = (track_edit % 8) + d
  elseif n==1 and d==-1 then
    track_edit = (track_edit + 6) % 8 + 1
  elseif n == 2 then
    gettrack(current_mem_cell,track_edit).k = util.clamp(gettrack(current_mem_cell,track_edit).k+d,0,gettrack(current_mem_cell,track_edit).n)
  elseif n==3 then
    gettrack(current_mem_cell,track_edit).n = util.clamp(gettrack(current_mem_cell,track_edit).n+d,1,32)
    gettrack(current_mem_cell,track_edit).k = util.clamp(gettrack(current_mem_cell,track_edit).k,0,gettrack(current_mem_cell,track_edit).n)
  end
  reer(track_edit)
  redraw()
end


function redraw()
  screen.aa(0)
  screen.clear()
  
  if view==0 and alt==0 then
    for i=1, 8 do
      if gettrack(current_mem_cell, i).mute == 1 then
       screen.move(17,i*7.70)
       screen.text_center("m")
      end
      screen.level((i == track_edit) and 15 or 4)
      screen.move(8, i*7.70)
      screen.text_center(gettrack(current_mem_cell,i).k)
      screen.move(25,i*7.70)
      screen.text_center(gettrack(current_mem_cell,i).n)
      for x=1,gettrack(current_mem_cell,i).n do
        screen.level(gettrack(current_mem_cell,i).pos==x and 15 or 2)
        screen.move(x*3 + 32, i*7.70)
        if gettrack(current_mem_cell,i).s[x] then
          screen.line_rel(0,-6)
        else
          screen.line_rel(0,-2)
        end
        screen.stroke()
      end
    end
  elseif view==0 and alt==1 then
    screen.level(4)
    screen.move(0, 8 + 11)
    screen.text("vol")
    screen.move(0, 16 + 11)
    screen.text(string.format("%.1f", params:get("output_level")))
    screen.move(0, 21 + 11)
    screen.line(20, 21 + 11)
    screen.move(0, 30 + 11)
    screen.text("bpm")
    screen.move(0, 40 + 11)
    screen.text(string.format("%.1f", clock.get_tempo()))
    if gettrack(current_mem_cell, track_edit).mute == 1 then
      screen.font_face(25)
      screen.font_size(6)
      screen.move(0, 60)
      screen.text("muted")
      screen.font_face(1)
      screen.font_size(8)
    end

    for i=1,8 do
      screen.level((i == track_edit) and 15 or 4)
      screen.move(25, i*7.70)
      screen.text_center(gettrack(current_mem_cell, i).rotation)
      for x=1,gettrack(current_mem_cell,i).n do
        screen.level(gettrack(current_mem_cell,i).pos==x and 15 or 2)
        screen.move(x*3 + 32, i*7.70)
        if gettrack(current_mem_cell,i).s[x] then
          screen.line_rel(0,-6)
        else
          screen.line_rel(0,-2)
        end
        screen.stroke()
      end
    end

  elseif view==1 and page==0 then
    if params:get(track_edit.."_send_midi") == 1 then
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      screen.text_center("1. vol : " .. string.format("%.1f", params:get(track_edit .. "_vol")))
      screen.move(64, 35)
      screen.text_center("2. envelope attack : " .. params:get(track_edit .. "_vol_env_atk"))
      screen.move(64, 45)
      screen.text_center("3. envelope release : " .. params:get(track_edit .. "_vol_env_rel"))
    else
      screen.move(5, 10)
      screen.level(15)
      screen.text("track : " .. track_edit)
      screen.move(120, 10)
      screen.text_right("page " .. page + 1)
      screen.move(5, 15)
      screen.line(121, 15)
      screen.move(64, 25)
      screen.level(4)
      screen.text_center("1. midi channel : " .. params:get(track_edit .. "_midi_chan"))
      screen.move(64, 35)
      screen.text_center("2. midi note : " .. params:get(track_edit .. "_midi_note"))
      if params:get(track_edit .."_use_scale") == 2 then
        screen.move(64, 45)
        screen.text_center("3. midi scale : " .. MusicUtil.SCALES[params:get(track_edit .. "_midi_scale")].name)
      end
    end

  elseif view==1 and page==1 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page + 1)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.move(64, 25)
    screen.level(4)
    if gettrack(current_mem_cell,track_edit).trig_logic == 0 then
      screen.text_center("1. trig logic : -")
      screen.move(64, 35)
      screen.level(1)
      screen.text_center("2. logic target : -")
      screen.level(4)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 1 then
      screen.text_center("1. trig logic : and")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 2 then
      screen.text_center("1. trig logic : or")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 3 then
      screen.text_center("1. trig logic : nand")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 4 then
      screen.text_center("1. trig logic : nor")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    elseif gettrack(current_mem_cell,track_edit).trig_logic == 5 then
      screen.text_center("1. trig logic : xor")
      screen.move(64, 35)
      screen.text_center("2. logic target : " .. gettrack(current_mem_cell,track_edit).logic_target)
    end
    screen.move(64, 45)
    screen.text_center("3. trig probability : " .. gettrack(current_mem_cell,track_edit).prob .. "%")

  elseif view==1 and page==2 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page + 1)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.move(64, 25)
    screen.level(4)
    screen.text_center("1. speed : " .. params:get(track_edit .. "_speed"))
    screen.move(64, 35)
    screen.text_center("2. start pos : " .. params:get(track_edit .. "_start_pos"))
    screen.move(64, 45)
    screen.text_center("3. end pos : " .. params:get(track_edit .. "_end_pos"))

  elseif view==1 and page==3 then
    screen.move(5, 10)
    screen.level(15)
    screen.text("track : " .. track_edit)
    screen.move(120, 10)
    screen.text_right("page " .. page + 1)
    screen.move(5, 15)
    screen.line(121, 15)
    screen.level(4)
    screen.move(64, 25)
    screen.text_center("1. filter cutoff : " .. math.floor(params:get(track_edit .. "_filter_cutoff") + 0.5))
    screen.move(64, 35)
    screen.text_center("2. delay send : " .. params:get(track_edit .. "_delay_send"))
    screen.move(64, 45)
    screen.text_center("3. reverb send : " .. params:get(track_edit .. "_reverb_send"))
  end
  screen.stroke()
  screen.update()
end
 
-- grid stuff - junklight

function g.key(x, y, state)
  -- use first column to switch track edit
  if x == 1 then
    track_edit = y
  end
  -- second column provides mutes
  if x == 2 and state == 1 then
    if gettrack(current_mem_cell, y).mute == 0 then
      gettrack(current_mem_cell, y).mute = 1
    elseif gettrack(current_mem_cell, y).mute == 1 then
      gettrack(current_mem_cell, y).mute = 0
    end
  end
  -- x 4-6, are used to open track parameters pages
  if y == 8 and x >= 4 and x <= 7 and state == 1 then
    view = 1
    page = x - 4
  else
    view = 0
  end
  -- start and stop button.
  if x == 4 and y == 7 and state == 1 then
    if stopped == 1 then
      stopped = 0
      clock_id = clock.run(pulse)
    else
      stopped = 1
      clock.cancel(clock_id)
    end
  end
  -- reset button
  if x == 5 and y == 7 and state == 1 then
    reset_pattern()
    if stopped == 1 then
      step()
    end
  end
  -- set pset load button
  if x == 8 and y == 7 and state == 1 then
    pset_load_mode = true
  elseif x == 8 and y == 7 and state == 0 then
    pset_load_mode = false
  end
  -- load pset 1-25
  if pset_load_mode then
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 1 then
      params:read(cellfromgrid(x,y))
      params:bang()
      print("loaded pset " .. cellfromgrid(x, y))
      current_pset = cellfromgrid(x, y)
      -- if you were stopped before loading, stay stopped after loading
      if stopped == 1 then
        run = false
      end
    end
  end
  -- copy button
  if x == 8 and y==8 and state == 1 then
    copy_mode = true
    copy_source_x = -1
    copy_source_y = -1
  elseif x == 8 and y==8 and state == 0 then
    copy_mode = false
    copy_source_x = -1
    copy_source_y = -1
  end
  -- memory cells
  -- switches on grid down
  if not copy_mode and not pset_load_mode then
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 1 then
      current_mem_cell = cellfromgrid(x,y)
      current_mem_cell_x = x
      current_mem_cell_y = y
      for i = 1, 8 do reer(i) end
    end
  else
    if y >= 1 and y <= 5 and x >= 4 and x <= 8 and state == 0 then
      if not pset_load_mode then
        -- copy functionality
        if copy_source_x == -1 then
          -- first button sets the source
          copy_source_x = x
          copy_source_y = y
        else
          -- second button copies source into target
          if copy_source_x ~= -1 and not ( copy_source_x == x and copy_source_y == y) then
            sourcecell = cellfromgrid( copy_source_x , copy_source_y )
            targetcell = cellfromgrid( x , y )
            memory_cell[targetcell] = simplecopy(memory_cell[sourcecell])
          end
        end
      end
    end
  end
  redraw()
end


function grid_redraw()
  if g == nil then
    -- bail if we are too early
    return
  end
  g:all(0)
  -- highlight current track
  g:led(1, track_edit, 15)
  -- track edit page buttons
  for page = 0, 3 do
      g:led(page + 4, 8, 3)
  end
  -- highlight page if open
  if view == 1 then
    g:led(page + 4, 8, 14)
  end
  -- mutes - bright for on, dim for off
  for i = 1,8 do
    if gettrack(current_mem_cell, i).mute == 1 then
      g:led(2, i, 15)
    else g:led(2, i, 4)
    end
  end
  -- memory cells
  for x = 4,8 do
    for y = 1,5 do
      g:led(x, y, 3)
    end
  end
  -- highlight active cell
  g:led(current_mem_cell_x, current_mem_cell_y, 15)
  if copy_mode then
    -- copy mode - blink the source if set
    if copy_source_x ~= -1 then
      if blink then
        g:led(copy_source_x, copy_source_y, 4)
      else
        g:led(copy_source_x, copy_source_y, 12)
      end
    end
  end
  -- start/stop
  if stopped == 0 then
    g:led(4, 7, 15)
  elseif stopped == 1 then
    if blink then
      g:led(4, 7, 4)
    else
      g:led(4, 7, 12)
    end
  end
  -- reset button
  g:led(5, 7, 3)
  -- load pset button
  if pset_load_mode then
    g:led(8, 7, 12)
  else g:led(8, 7, 3) end
  -- copy button
  if copy_mode  then
    g:led(8, 8, 14)
  else
    g:led(8, 8, 3)
  end
  g:refresh()
end


function savestate()
  local file = io.open(_path.data .. "foulplay/foulplay-pattern.data", "w+")
  io.output(file)
  io.write("v1" .. "\n")
  for j = 1, 25 do
    for i = 1, 8 do
      io.write(memory_cell[j][i].k .. "\n")
      io.write(memory_cell[j][i].n .. "\n")
      io.write(memory_cell[j][i].prob .. "\n")
      io.write(memory_cell[j][i].trig_logic .. "\n")
      io.write(memory_cell[j][i].logic_target .. "\n")
      io.write(memory_cell[j][i].rotation .. "\n")
      io.write(memory_cell[j][i].mute .. "\n")
    end
  end
  io.close(file)
end

function loadstate()
  local file = io.open(_path.data .. "foulplay/foulplay-pattern.data", "r")
  if file then
    print("datafile found")
    io.input(file)
    if io.read() == "v1" then
      for j = 1, 25 do
        for i = 1, 8 do
          memory_cell[j][i].k = tonumber(io.read())
          memory_cell[j][i].n = tonumber(io.read())
          memory_cell[j][i].prob = tonumber(io.read())
          memory_cell[j][i].trig_logic = tonumber(io.read())
          memory_cell[j][i].logic_target = tonumber(io.read())
          memory_cell[j][i].rotation = tonumber(io.read())
          memory_cell[j][i].mute = tonumber(io.read())
        end
      end
    else
      print("invalid data file")
    end
    io.close(file)
  end
  for i = 1, 8 do reer(i) end
end
