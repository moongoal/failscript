if SCRIPT_DIRECTORY == nil then
    SCRIPT_DIRECTORY = './'
end

-- config
--CFG_FILE = 'D:\\Users\\moongoal\\SteamLibrary\\steamapps\\common\\X-Plane 11\\Resources\\plugins\\FlyWithLua\\Scripts\\failprofile.csv'
CFG_FILE = SCRIPT_DIRECTORY .. 'failprofile.csv'

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
STATE_FAILED = 0

-- Enable debug mode if running standalone
-- Debug mode will not interact with X-Plane nut instead output to console every dataref change
if XPLANE_VERSION then
    STATE_DEBUG = 0
else
    STATE_DEBUG = 1
end

function set_dref(dref_name, dref_value)
    if STATE_DEBUG == 1 then
        print(dref_name .. ' = ' .. dref_value)
    else
        set(dref_name, dref_value)
    end
end

function log(text)
    local msg = 'failscript: ' .. text

    if STATE_DEBUG == 1 then
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
    if STATE_FAILED == 1 then
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

    STATE_FAILED = 1
end

function set_single_failure(fail_data)
    if fail_data["random"] <= fail_data["p_start"] then
        set_dref(fail_data["dataref"], FAILURE_INOP)
        log(fail_data["dataref"] .. ' has failed')
    end
end

function init()
    math.randomseed(os.time())

    set_failures()
end

init()