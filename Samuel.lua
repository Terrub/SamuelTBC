----------------------------------------------------------------
-- "UP VALUES" FOR SPEED ---------------------------------------
----------------------------------------------------------------

local mathMin = math.min;
local stringFind = string.find;
local tableInsert = table.insert;
local tableRemove = table.remove;
local tostring = tostring;
local type = type;
local error = error;
local pairs = pairs;
local select = select;

----------------------------------------------------------------
-- CONSTANTS THAT SHOULD BE GLOBAL PROBABLY --------------------
----------------------------------------------------------------

local EN_GB_PAT_CHAT_MSG_SPELL_SELF_DAMAGE = "^Your (.-) ";

local ERR_UNEXPECTED_NIL_VALUE = "Expected the following value but got nil:"

local SCRIPTHANDLER_ON_EVENT = "OnEvent";
local SCRIPTHANDLER_ON_UPDATE = "OnUpdate";
local SCRIPTHANDLER_ON_DRAG_START = "OnDragStart";
local SCRIPTHANDLER_ON_DRAG_STOP = "OnDragStop";

----------------------------------------------------------------
-- HELPER FUNCTIONS --------------------------------------------
----------------------------------------------------------------

--  These should be moved into the core at one point.

local function merge(left, right)

    local t = {};

    if type(left) ~= "table" or type(right) ~= "table" then

        error("Usage: merge(left <table>, right <table>)");

    end

    -- copy left into temp table.
    for k, v in pairs(left) do

        t[k] = v;

    end

    -- Add or overwrite right values.
    for k, v in pairs(right) do

        t[k] = v;

    end

    return t;

end

--------

local function toColourisedString(value)

    local val;

    if type(value) == "string" then

        val = "|cffffffff" .. value .. "|r";

    elseif type(value) == "number" then

        val = "|cffffff33" .. tostring(value) .. "|r";

    elseif type(value) == "boolean" then

        val = "|cff9999ff" .. tostring(value) .. "|r";

    elseif value == nil then

        val = "|cff9900ffnil|r";

    end

    return val;

end

--------

local function prt(message)

    if (message and message ~= "") then

        if type(message) ~= "string" then

            message = tostring(message);

        end

        DEFAULT_CHAT_FRAME:AddMessage(message);

    end

end;

--------

----------------------------------------------------------------
-- SAMUEL ADDON ------------------------------------------------
----------------------------------------------------------------

Samuel = CreateFrame("FRAME", "Samuel", UIParent);

local this = Samuel;

----------------------------------------------------------------
-- INTERNAL CONSTANTS ------------------------------------------
----------------------------------------------------------------

local SLAM_CAST_TIME = 1.5;
local SLAM_TOTAL_RANKS_IMP_SLAM = 5;
local SLAM_TOTAL_IMP_SLAM_CAST_REDUCTION = 0.5;

----------------------------------------------------------------
-- DATABASE KEYS -----------------------------------------------
----------------------------------------------------------------

-- IF ANY OF THE >>VALUES<< CHANGE YOU WILL RESET THE STORED
-- VARIABLES OF THE PLAYER. EFFECTIVELY DELETING THEIR CUSTOM-
-- ISATION SETTINGS!!!
--
-- Changing the constant itself may cause errors in some cases.
-- Or outright kill the addon alltogether.

-- #TODO:   Make these version specific, allowing full
--          backwards-compatability. Though doing so manually
--          is very error prone. Not sure how to do this auto-
--          matically. Yet.
--
--          Consider doing something like a property list.
--          When changing a property using the slash-cmds or
--          perhaps an in-game editor, we can change the version
--          and keep a record per version.

local IS_MARKER_SHOWN = "is_marker_shown";
local IS_ADDON_ACTIVATED = "is_addon_activated";
local IS_ADDON_LOCKED = "is_addon_locked";
local MARKER_SIZE = "marker_size";
local POSITION_POINT = "position_point";
local POSITION_X = "position_x";
local POSITION_Y = "position_y";
local ACTIVE_ALPHA = "active_alpha";
local INACTIVE_ALPHA = "inactive_alpha";
local DB_VERSION = "db_version";

local default_db = {
    [IS_MARKER_SHOWN] = false;
    [IS_ADDON_ACTIVATED] = false;
    [IS_ADDON_LOCKED] = true;
    [MARKER_SIZE] = 1.5;
    [POSITION_POINT] = "CENTER";
    [POSITION_X] = 0;
    [POSITION_Y] = -120;
    [ACTIVE_ALPHA] = 1;
    [INACTIVE_ALPHA] = 0.3;
    [DB_VERSION] = 3;
};

----------------------------------------------------------------
-- PRIVATE VARIABLES -------------------------------------------
----------------------------------------------------------------

local initialisation_event = "ADDON_LOADED";

local progress_bar;
local marker;

local auto_repeat_spell_active = false;
local auto_attack_active = false;

local updateRunTime = 0;
local fps = 30; -- target FPS.
local update_display_timer = ( 1 / fps );
local last_update = GetTime();
local total_swing_time = 1; -- the y in x/y * 100% calc.
local total_range_time = 1; -- the other y in the x/y * 100% calc.

local unit_name;
local realm_name;
local profile_id;
local db;

local reset_timer_spell_names;
local event_handlers;
local command_list;

local last_swing;
local last_range;

local default_width = 200;
local default_height = 5;

----------------------------------------------------------------
-- PRIVATE FUNCTIONS -------------------------------------------
----------------------------------------------------------------

local function report(label, message)

    label = tostring(label);
    message = tostring(message);

    local str = "|cff22ff22Samuel|r - |cff999999" .. label .. ":|r " .. message;

    prt(str);

end

--------

local function reportError(label, message)

    label = tostring(label);
    message = tostring(message);

    local str = "|cff22ff22Samuel|r - |cffcc5555ERROR|r " .. label .. ": " .. message;

    prt(str);

end

--------

local function reportDebugMsg(message)

    message = tostring(message);

    local str = "|cff22ff22Samuel|r - |cffcccc55Debug Message:|r " .. message;

    prt(str);

end

--------

local function deactivateSwingTimer()

    this:Hide();

end

--------

local function activateSwingTimer()

    this:Show();

    last_update = GetTime();

end

--------

local function resetVisibility()

    -- Turn on if player is in combat
    if UnitAffectingCombat("player") then

        activateSwingTimer();

    else

        deactivateSwingTimer();

    end

end

--------

local function updateSlamMarker(p_total_time)

    if (marker) then

        marker:SetWidth( (default_width / p_total_time) * db[MARKER_SIZE] );

    end

end

--------

local function resetSwingTimer()

    last_swing = GetTime();

end

--------

local function resetRangeTimer()

    last_range = GetTime();

end

--------

local function setMarkerSize(time_in_seconds)

    -- Stop arsin about!
    if time_in_seconds == db[MARKER_SIZE] then return end;

    time_in_seconds = tonumber(time_in_seconds);

    if not time_in_seconds then

        report("setMarkerSize expects", "a number in seconds");

        return;

    end

    if time_in_seconds < 0 then

        report("setMarkerSize expects", "time in seconds to be 0 or more");

        return;

    end

    -- Update local database
    db[MARKER_SIZE] = time_in_seconds;

    report("Saved marker size to", db[MARKER_SIZE]);

end

--------

local function updateSwingTime()

    -- http://vanilla-wow.wikia.com/wiki/API_UnitAttackSpeed
    total_swing_time = UnitAttackSpeed("player");

    -- http://wowwiki.wikia.com/wiki/API_UnitRangedDamage
    total_range_time = UnitRangedDamage("player");

    -- reportDebugMsg("Updated speeds to: " .. total_swing_time .. "s and " .. total_range_time .. "s");

end

--------

local function activateAutoAttackSymbol()

    if auto_attack_active or auto_repeat_spell_active then

        this:SetAlpha(db[ACTIVE_ALPHA]);

    end

end

--------

local function deactivateAutoAttackSymbol()

    if not (auto_attack_active or auto_repeat_spell_active) then

        this:SetAlpha(db[INACTIVE_ALPHA]);

    end

end

--------

local function populateSwingResetSpellNames()

    reset_timer_spell_names = {
        ["Heroic Strike"] = true,
        ["Slam"] = true,
        ["Cleave"] = true,
        ["Raptor Strike"] = true,
        ["Maul"] = true,
    }

end

--------

local function addEvent(event_name, eventHandler)

    if  (not event_name)
    or  (event_name == "")
    or  (not eventHandler)
    or  (type(eventHandler) ~= "function") then

        reportError("Usage", "addEvent(event_name <string>, eventHandler <function>)");

        return;

    end

    event_handlers[event_name] = eventHandler;

    this:RegisterEvent(event_name);

    -- reportDebugMsg("Registered event: " .. event_name);

end

--------

local function removeEvent(event_name)

    local eventHandler = event_handlers[event_name];

    if eventHandler then

        -- GC should pick this up when a new assignment happens
        event_handlers[event_name] = nil;

    end

    this:UnregisterEvent(event_name);

end

--------
-- #TODO: This looks an awefull lot like a class... again.
local function addSlashCommand(name, command, command_description, db_property)

    if  (not name)
    or  (name == "")
    or  (not command)
    or  (type(command) ~= "function")
    or  (not command_description)
    or  (command_description == "") then

        reportError("Usage", "addSlashCommand(name <string>, command <function>, command_description <string> [, db_property <string>])");

        return;

    end

    -- reportDebugMsg("Attempt to add slash command:\n[name]: " .. name .. "\n[description]: " .. command_description);

    command_list[name] = {
        ["execute"] = command,
        ["description"] = command_description
    };

    if (db_property) then

        if (type(db_property) ~= "string" or db_property == "") then

            error("db_property must be a non-empty string.");

        end

        if (db[db_property] == nil) then

            error('The internal database property: "' .. db_property .. '" could not be found.');

        end
        -- prt("Add the database property to the command list");
        command_list[name]["value"] = db_property;

    end

end

--------

local function finishInitialisation()

    -- we only need this once
    this:UnregisterEvent("PLAYER_LOGIN");

    updateSwingTime();

end

--------

local function storeLocalDatabaseToSavedVariables()

    -- #OPTION: We could have local variables for lots of DB
    --          stuff that we can load into the db Object
    --          before we store it.
    --
    --          Should probably make a list of variables to keep
    --          track of which changed and should be updated.
    --          Something we can just loop through so load and
    --          unload never desync.

    -- Commit to local storage
    SamuelDB[profile_id] = db;

end

--------

local function validatePlayerTalents()

    --report("CHARACTER_POINTS_CHANGED", arg1);

end

--------

local function activateAutoAttack()

    auto_attack_active = true;

    activateAutoAttackSymbol();

end

--------

local function deactivateAutoAttack()

    auto_attack_active = false;

    deactivateAutoAttackSymbol();

end

--------

local function activateAutoRepeatSpell()

    auto_repeat_spell_active = true;

    activateAutoAttackSymbol();

    -- reportDebugMsg("Activated Auto Repeat Spell");

end

--------

local function deactivateAutoRepeatSpell()

    auto_repeat_spell_active = false;

    deactivateAutoAttackSymbol();

    -- reportDebugMsg("Deactivated Auto Repeat Spell");

end

--------

local function eventCoordinator(...)

    -- given:
    -- event <string> The event name that triggered.
    -- arg1, arg2, ..., arg9 <*> Given arguments specific to the event.

    local num_args = select('#', ...);
    local eventHandler = event_handlers[event];

    if not eventHandler then

        reportError("Could not find eventHandler for", event);

        return;

    end

    -- reportDebugMsg("Calling eventHandler for: " .. event);

    eventHandler(...);

end

--------

local function removeEvents()

    for event_name, eventHandler in pairs(event_handlers) do

        if eventHandler then

            removeEvent(event_name);

        end

    end

end

--------

local function updateDisplay(self, elapsed)

    -- local elapsed = GetTime() - last_update;

    -- elapsed is the total time since last frame update.
    -- we have to add this to our current running total timer
    -- to know when to actually do something next frame.
    updateRunTime = updateRunTime + elapsed;

    if not (auto_attack_active or auto_repeat_spell_active) then

        return;

    end

    local last_time;
    local total_time;

    -- This is the actual update loop.
    while (updateRunTime >= update_display_timer) do

        if auto_attack_active then

            last_time = last_swing;
            total_time = total_swing_time;

        elseif auto_repeat_spell_active then

            last_time = last_range;
            total_time = total_range_time;

        end

        if not total_time or not last_time then

            reportError(ERR_UNEXPECTED_NIL_VALUE, "total_time or last_time");

            return;

        end

        updateSlamMarker(total_time);

        local current_time = GetTime() - last_time;
        local ratio = mathMin((current_time / total_time), 1);

        progress_bar:SetWidth(ratio * default_width);

        updateRunTime = updateRunTime - update_display_timer;

    end

    -- last_update = GetTime();

end

--------

local function createProgressBar()

    -- We already made one, no use in making another.
    if progress_bar then

        return;

    end

    progress_bar = CreateFrame("FRAME", nil, this);

    progress_bar:SetBackdrop(
        {
            ["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
        }
    );

    progress_bar:SetBackdropColor(0.7, 0.7, 0.7, 1);

    progress_bar:SetWidth(1);
    progress_bar:SetHeight(default_height);

    progress_bar:SetPoint("LEFT", 0, 0);

end

--------

local function hideMarker()

    db[IS_MARKER_SHOWN] = false;

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (marker) then

        marker:Hide();

    end

    report("Marker is", "Hidden");

end

--------

local function showMarker()

    db[IS_MARKER_SHOWN] = true;

    -- Addon could be inactive or some other reason
    -- we don't actually have the frame on hand.
    if (marker) then

        marker:Show();

    end

    report("Marker is", "Shown");

end

--------

local function toggleMarkerVisibility()

    if db[IS_MARKER_SHOWN] then

        hideMarker();

    else

        showMarker();

    end

end

--------

local function createMarker()

    -- We already made one, no use in making another.
    if marker then

        return;

    end

    marker = CreateFrame("FRAME", nil, this);

    marker:SetBackdrop(
        {
            ["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
        }
    );
    marker:SetBackdropColor(1, 0, 0, 0.7);

    marker:SetPoint("RIGHT", 0, 0);

    marker:SetHeight(default_height);

    if (progress_bar) then
        -- Making sure slam marker is visually on top of the progress bar.
        marker:SetFrameLevel(progress_bar:GetFrameLevel()+1);

    end

    if db[IS_MARKER_SHOWN] then

        marker:Show();

    else

        marker:Hide();

    end

end

--------

local function printSlashCommandList()

    report("Listing", "Slash commands");

    local str;
    local description;
    local current_value;

    for name, cmd_object in pairs(command_list) do

        description = cmd_object.description;

        if (not description) then

            error('Attempt to print slash command with name:"' .. name .. '" without valid description');

        end

        str = "/sam " .. name .. " " .. description;

        -- If the slash command sets a value we should have
        if (cmd_object.value) then

            str = str .. " (|cff666666Currently:|r " .. toColourisedString(db[cmd_object.value]) .. ")";

        end

        prt(str);

    end



end

--------

local function startMoving()

    this:StartMoving();

end

--------

local function stopMovingOrSizing()

    this:StopMovingOrSizing();

    db[POSITION_POINT], _, _, db[POSITION_X], db[POSITION_Y] = this:GetPoint();

end

--------

local function unlockAddon()

    -- Make the left mouse button trigger drag events
    this:RegisterForDrag("LeftButton");

    -- Set the start and stop moving events on triggered events
    this:SetScript(SCRIPTHANDLER_ON_DRAG_START, startMoving);
    this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, stopMovingOrSizing);

    -- Make the frame react to the mouse
    this:EnableMouse(true);

    -- Make the frame movable
    this:SetMovable(true);

    -- Show ourselves so we can be moved
    activateSwingTimer();

    db[IS_ADDON_LOCKED] = false;

    report("Swing timer bar", "Unlocked");

end

--------

local function lockAddon()

    -- Stop the frame from being movable
    this:SetMovable(false);

    -- Remove all buttons from triggering drag events
    this:RegisterForDrag();

    -- Nil the 'OnSragStart' script event
    this:SetScript(SCRIPTHANDLER_ON_DRAG_START, nil);
    this:SetScript(SCRIPTHANDLER_ON_DRAG_STOP, nil);

    -- Disable mouse interactivity on the frame
    this:EnableMouse(false)

    -- reset our visibility
    resetVisibility();

    db[IS_ADDON_LOCKED] = true;

    report("Swing timer bar", "Locked");

end

--------

local function toggleLockToScreen()

    -- Inversed logic to lock the addon if db[IS_ADDON_LOCKED] returns 'nil' for some reason.
    if not db[IS_ADDON_LOCKED] then

        lockAddon();

    else

        unlockAddon();

    end

end

--------

local function isCombatEventSwing(p_combat_event)

    local combat_event_is_swing = false;

    if p_combat_event == "SWING_MISSED"
    or p_combat_event == "SWING_DAMAGE" then

        combat_event_is_swing = true;

    end

    -- reportDebugMsg(p_combat_event .. " is swing: " .. toColourisedString(combat_event_is_swing));

    return combat_event_is_swing;

end

--------

local function isCombatEventRanged(p_combat_event)

    local combat_event_is_ranged = false;

    if p_combat_event == "RANGE_MISSED"
    or p_combat_event == "RANGE_DAMAGE" then

        combat_event_is_ranged = true;

    end

    -- reportDebugMsg(p_combat_event .. " is ranged: " .. toColourisedString(combat_event_is_ranged));

    return combat_event_is_ranged;

end

--------

local function isCombatEventSpell(p_combat_event)

    local combat_event_is_spell = false;

    if p_combat_event == "SPELL_MISSED"
    or p_combat_event == "SPELL_DAMAGE" then

        combat_event_is_spell = true;

    end

    -- reportDebugMsg(p_combat_event .. " is spell: " .. toColourisedString(combat_event_is_spell));

    return combat_event_is_spell;

end

--------

local function isSpellNameResetSpell(p_spell_name)

    local spell_name_is_reset_spell = reset_timer_spell_names[p_spell_name];

    -- reportDebugMsg(p_spell_name .. " is reset spell: " .. toColourisedString(spell_name_is_reset_spell));

    return spell_name_is_reset_spell;

end

--------

local function combatLogEventHandler(self, event, ...)

    -- local n = select('#', ...);
    local t = {...};

    local combat_event = t[2];
    local source_guid = t[3];

    if source_guid ~= UnitGUID("player") then

        return;

    end

    if isCombatEventSwing(combat_event) then

        resetSwingTimer();

    elseif isCombatEventRanged(combat_event) then

        resetRangeTimer();

    elseif isCombatEventSpell(combat_event) then

        local spell_name = t[10];

        -- reportDebugMsg("Spell name: " .. spell_name);

        if isSpellNameResetSpell(spell_name) then

            resetSwingTimer();

        end

    end

end

--------

local function populateRequiredEvents()

    addEvent("COMBAT_LOG_EVENT_UNFILTERED", combatLogEventHandler);

    addEvent("UNIT_ATTACK_SPEED", updateSwingTime);

    addEvent("PLAYER_REGEN_DISABLED", activateSwingTimer);
    addEvent("PLAYER_REGEN_ENABLED", deactivateSwingTimer);

    addEvent("PLAYER_ENTER_COMBAT", activateAutoAttack);
    addEvent("PLAYER_LEAVE_COMBAT", deactivateAutoAttack);

    addEvent("START_AUTOREPEAT_SPELL", activateAutoRepeatSpell);
    addEvent("STOP_AUTOREPEAT_SPELL", deactivateAutoRepeatSpell);

    addEvent("PLAYER_LOGIN", finishInitialisation);

end

--------

local function constructAddon()

    this:SetWidth(default_width);
    this:SetHeight(default_height);

    this:SetBackdrop(
        {
            ["bgFile"] = "Interface/CHATFRAME/CHATFRAMEBACKGROUND"
        }
    );

    this:SetBackdropColor(0, 0, 0, 1);

    this:SetPoint(db[POSITION_POINT], db[POSITION_X], db[POSITION_Y]);

    if (not db[IS_ADDON_LOCKED]) then unlockAddon() end;

    -- CREATE CHILDREN
    createProgressBar();
    createMarker();

    resetSwingTimer();
    resetRangeTimer();
    resetVisibility();

    populateSwingResetSpellNames();
    populateRequiredEvents();

    this:SetScript(SCRIPTHANDLER_ON_UPDATE, updateDisplay);

end

--------

local function destructAddon()


    -- Stop frame updates
    this:SetScript(SCRIPTHANDLER_ON_UPDATE, nil);

    -- Remove all registered events
    removeEvents();

    deactivateSwingTimer();
    deactivateAutoAttack();
    deactivateAutoRepeatSpell();

end

--------

local function activateAddon()

    if db[IS_ADDON_ACTIVATED] then

        return;

    end

    constructAddon();

    db[IS_ADDON_ACTIVATED] = true;

    report("is now", "Activated");

end

--------

local function deactivateAddon()

    if not db[IS_ADDON_ACTIVATED] then

        return;

    end

    destructAddon();

    db[IS_ADDON_ACTIVATED] = false;

    -- This is here and not in the destructor because
    -- loadSavedVariables is not in the constructor either.
    storeLocalDatabaseToSavedVariables();

    report("is now", "Deactivated");

end

--------

local function toggleAddonActivity()

    if not db[IS_ADDON_ACTIVATED] then

        activateAddon();

    else

        deactivateAddon();

    end

end

--------

local function slashCmdHandler(message, chat_frame)

    local _,_,command_name, params = stringFind(message, "^(%S+) *(.*)");

    -- Stringify it
    command_name = tostring(command_name);

    -- Pull the given command from our list.
    local command = command_list[command_name];

    if (command) then
        -- Run the command we found.
        if (type(command.execute) ~= "function") then

            reportError("Attempt to execute slash command without execution function", command_name);

            return;

        end

        command.execute(params);

    else
        -- prt("Print our available command list.");
        printSlashCommandList();

    end

end

--------

local function loadProfileID()

    unit_name = UnitName("player");
    realm_name = GetRealmName();
    profile_id = unit_name .. "-" .. realm_name;

end

--------

local function loadSavedVariables()

    -- First time install
    if not SamuelDB then
        SamuelDB = {};
    end

    -- this should produce an error if profile_id is not yet set, as is intended.
    db = SamuelDB[profile_id];

    -- This means we have a new char.
    if not db then
        db = default_db
    end

    -- In this case we have a player with an older version DB.
    if (not db[DB_VERSION]) or (db[DB_VERSION] < default_db[DB_VERSION]) then

        -- For now we just blindly attempt to merge.
        db = merge(default_db, db);

    end

end

--------

local function populateSlashCommandList()

    -- For now we just reset this thing.
    command_list = {};

    addSlashCommand(
        "setMarkerSize",
        setMarkerSize,
        '[|cffffff330+|r] |cff999999-- Set the amount of seconds of your swing time the marker should cover.|r',
        MARKER_SIZE
    );

    addSlashCommand(
        "showMarker",
        toggleMarkerVisibility,
        '<|cff9999fftoggle|r> |cff999999-- Toggle whether the red marker is showing.|r',
        IS_MARKER_SHOWN
    );

    addSlashCommand(
        "lock",
        toggleLockToScreen,
        '<|cff9999fftoggle|r> |cff999999-- Toggle whether the bar is locked to the screen.|r',
        IS_ADDON_LOCKED
    );

    addSlashCommand(
        "activate",
        toggleAddonActivity,
        '<|cff9999fftoggle|r> |cff999999-- Toggle whether the AddOn itself is active.|r',
        IS_ADDON_ACTIVATED
    );

end

--------

local function initialise()

    loadProfileID();
    loadSavedVariables();

    this:UnregisterEvent(initialisation_event);

    event_handlers = {};

    populateSlashCommandList();

    this:SetScript(SCRIPTHANDLER_ON_EVENT, eventCoordinator);

    addEvent("PLAYER_LOGOUT", storeLocalDatabaseToSavedVariables);

    if db[IS_ADDON_ACTIVATED] then

        constructAddon();

    end

end

-- Add slashcommand match entries into the global namespace for the client to pick up.
SLASH_SAMUEL1 = "/sam";
SLASH_SAMUEL2 = "/samuel";

-- And add a handler to react on the above matches.
SlashCmdList["SAMUEL"] = slashCmdHandler;

this:SetScript(SCRIPTHANDLER_ON_EVENT, initialise);
this:RegisterEvent(initialisation_event);
