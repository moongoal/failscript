if SCRIPT_DIRECTORY == nil then
    SCRIPT_DIRECTORY = './'
end

-- config
--CFG_FILE = 'D:\\Users\\moongoal\\SteamLibrary\\steamapps\\common\\X-Plane 11\\Resources\\plugins\\FlyWithLua\\Scripts\\failprofile.csv'
CFG_FILE = SCRIPT_DIRECTORY .. 'failprofile.csv'
CFG_MAX_TIME_BETWEEN_FAILURES = 3 -- Max mean time between failures (hrs)
CFG_MAX_FAIL_SPEED = 300 -- Max failure speed (kts, groundspeed)
CFG_MAX_FAIL_HEIGHT = 40000 -- Max failure height (feet, AGL)

-- failure_enum
-- from https://forums.x-plane.org/index.php?/forums/topic/34811-what-type-is-failure_enum/
FAILURE_WORKING = 0 -- = always working
FAILURE_MEAN_TIME = 1 -- = mean time until failure
FAILURE_EXACT_TIME = 2 -- = exact time until failure
FAILURE_EXACT_SPEED = 3 -- = fail at exact speed KIAS
FAILURE_EXACT_HEIGHT = 4 -- = fail at exact altitude AGL
FAILURE_CTRL = 5 -- = fail if CTRL f or JOY
FAILURE_INOP = 6 -- = inoperative

-- state
STATE_FAILED = false
STATE_FAIL_SPEED = 0 -- Speed at which FAILURE_EXACT_SPEED failures will occur - computed in init()
STATE_FAIL_HEIGHT = 0 -- Height at which FAILURE_EXACT_SPEED failures will occur - computed in init()
STATE_FAIL_TIME = 0 -- Next time systems will fail
STATE_FAIL_LATER = {} -- Array of fail_data not yet failed
STATE_FAIL_AT_SPEED = {} -- Array of fail_data not yet failed
STATE_FAIL_AT_HEIGHT = {} -- Array of fail_data not yet failed
STATE_TIME_START = os.time() -- Start of simulation

-- Enable debug mode if running standalone
-- Debug mode will not interact with X-Plane nut instead output to console every dataref change
if XPLANE_VERSION then
    STATE_DEBUG = false
else
    STATE_DEBUG = true

    function do_sometimes(dummy)
    end
end

function set_dref(dref_name, dref_value)
    if STATE_DEBUG == true then
        print(dref_name .. ' = ' .. dref_value)
    else
        set(dref_name, dref_value)
    end
end

function get_dref(dref_name)
    if STATE_DEBUG == true then
        return nil
    else
        get(dref_name)
    end
end

function log(text)
    local msg = 'failscript: ' .. text

    if STATE_DEBUG == true then
        print(msg)
    else
        logMsg(msg)
    end
end

function split(text, sep)
    local i = 0
    local t = text .. sep
    local out = {}

    for w in t:gmatch("(.-),") do
        out[i] = w
        i = i + 1
    end

    return out
end

function parse_fail_prob(prob_str)
    local probs = {
        ["l"] = 0.00001,
        ["m"] = 0.0001,
        ["h"] = 0.0005,
        ["n"] = 0,
        ["a"] = 1,
    }

    return probs[prob_str]
end

function parse_profile_csv(csv)
    local profile = {}

    for line in csv do
        local record = split(line, ',')
        local dataref = record[0]
        local p_start = parse_fail_prob(record[1])

        if p_start ~= 0 then -- don't store disabled datarefs
            profile[dataref] = p_start
        end
    end

    return profile
end

function read_profile(path)
    local csv = io.lines(path)
    local profile = parse_profile_csv(csv)

    return profile
end

function set_failures()
    if STATE_FAILED == true then
        return
    end

    log('Loading profile...')
    local any_failure = false
    local profile = read_profile(CFG_FILE)

    log('Generating failures...')
    for d, p in pairs(profile) do
        local r = math.random()
        local fail_data = {
            ["dataref"] = d,
            ["p_start"] = p,
            ["random"] = r
        }

        set_single_failure(fail_data)
        any_failure = true
    end

    if any_failure == true then
        log('No failure active.')
    end

    STATE_FAILED = true
end

function set_single_failure(fail_data)
    if fail_data["random"] <= fail_data["p_start"] then
        local ft = math.random(1, 3) -- Fail type: 1 immediate, 2 mean time, 3 at speed, 4 at height

        if ft == 1 then
            set_immediate_failure(fail_data)
        elseif ft == 2 then
            set_delayed_failure(fail_data)
        elseif ft == 3 then
            set_speed_failure(fail_data)
        else
            set_height_failure(fail_data)
        end
    end
end

function set_immediate_failure(fail_data)
    set_dref(fail_data["dataref"], FAILURE_INOP)
    log(fail_data["dataref"] .. ' has failed')
end

function set_delayed_failure(fail_data)
    set_dref(fail_data["dataref"], FAILURE_MEAN_TIME)
    STATE_FAIL_LATER[#STATE_FAIL_LATER+1] = fail_data

    log(fail_data["dataref"] .. ' will fail later')
end

function set_speed_failure(fail_data)
    set_dref(fail_data["dataref"], FAILURE_EXACT_SPEED)
    STATE_FAIL_AT_SPEED[#STATE_FAIL_AT_SPEED+1] = fail_data

    log(fail_data["dataref"] .. ' will fail at exact speed')
end

function set_height_failure(fail_data)
    set_dref(fail_data["dataref"], FAILURE_EXACT_HEIGHT)
    STATE_FAIL_AT_HEIGHT[#STATE_FAIL_AT_HEIGHT+1] = fail_data

    log(fail_data["dataref"] .. ' will fail at exact height')
end

function set_next_fail_time()
    local next_fail_relative = math.random() * CFG_MAX_TIME_BETWEEN_FAILURES * 3600

    STATE_FAIL_TIME = STATE_FAIL_TIME + next_fail_relative
end

function init()
    math.randomseed(os.time())

    STATE_FAIL_SPEED = math.random() * CFG_MAX_FAIL_SPEED
    STATE_FAIL_HEIGHT = math.random() * CFG_MAX_FAIL_HEIGHT
    STATE_FAIL_TIME = STATE_TIME_START

    -- FIXME: Implement own timed failure management to avoid catastrophic kaboom
    -- set_dref("sim/operation/failures/mean_time_between_failure_hrs", math.random() * CFG_MAX_TIME_BETWEEN_FAILURES)
    -- set_dref("sim/operation/failures/enable_random_failures", 1)

    set_next_fail_time()
    set_failures()

    if STATE_DEBUG == true then
        log('Fail speed is ' .. STATE_FAIL_SPEED)
        log('Fail height is ' .. STATE_FAIL_HEIGHT)
    end

    local needs_fail_loop = (#STATE_FAIL_AT_SPEED > 0) or (#STATE_FAIL_AT_HEIGHT > 0) or (#STATE_FAIL_LATER > 0)

    if needs_fail_loop then
        do_sometimes('fail_loop')
    end
end

function fail_loop()
    local speed = get_dref('sim/flightmodel/position/groundspeed') * 1.943844 -- m/s to kn
    local height = get_dref('sim/flightmodel/position/y_agl') * 3.28084 -- m to ft

    if speed > STATE_FAIL_SPEED then
        for i, fail_data in pairs(STATE_FAIL_AT_SPEED) do
            set_immediate_failure(fail_data)
        end

        STATE_FAIL_AT_SPEED = {}
    end

    if height > STATE_FAIL_HEIGHT then
        for i, fail_data in pairs(STATE_FAIL_AT_HEIGHT) do
            set_immediate_failure(fail_data)
        end

        STATE_FAIL_AT_HEIGHT = {}
    end

    if #STATE_FAIL_LATER > 0 then
        local cur_time = os.time()

        if cur_time >= STATE_FAIL_TIME then
            local fail_data = table.remove(STATE_FAIL_LATER, 1)

            set_immediate_failure(fail_data)
            set_next_fail_time()
        end
    end
end

init()
