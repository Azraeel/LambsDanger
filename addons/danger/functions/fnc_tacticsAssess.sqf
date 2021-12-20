#include "script_component.hpp"
/*
 * Author: nkenny
 * Group leader assesses situation and calls manoeuvres or support assets as necessary
 *
 * Arguments:
 * 0: group leader <OBJECT>
 *
 * Return Value:
 * bool
 *
 * Example:
 * [bob] call lambs_danger_fnc_tacticsAssess;
 *
 * Public: No
*/
#define TACTICS_HIDE 0
#define TACTICS_FLANK 1
#define TACTICS_GARRISON 2
#define TACTICS_ASSAULT 3
#define TACTICS_SUPPRESS 4
#define TACTICS_ATTACK 5
#define RANGE_NEAR 120
#define RANGE_MID 220
#define RANGE_LONG 300
#define RANGE_THREAT 450

params [["_unit", objNull, [objNull]]];

// check if group AI disabled
private _group = group _unit;

// set variable
_group setVariable [QGVAR(isExecutingTactic), true];
_group setVariable [QGVAR(contact), time + 600];

// set current task
_unit setVariable [QEGVAR(main,currentTarget), objNull, EGVAR(main,debug_functions)];
_unit setVariable [QEGVAR(main,currentTask), "Tactics Assess", EGVAR(main,debug_functions)];

// get max data range ~ reduced for forests or cities - nkenny
private _pos = getPosATL _unit;
private _range = (850 * (1 - (_pos getEnvSoundController "houses") - (_pos getEnvSoundController "trees") - (_pos getEnvSoundController "forest") * 0.5)) max 120;

// gather data
private _unitCount = count units _unit;
private _enemies = (_unit targets [true, _range]) select {_unit knowsAbout _x > 1};
private _plan = [];

// leader assess EH
[QGVAR(OnAssess), [_unit, _group, _enemies]] call EFUNC(main,eventCallback);

// sort plans
_pos = [];
if !(_enemies isEqualTo [] || {_unitCount < random 3}) then {

    // get modes
    private _speedMode = (speedMode _unit) isEqualTo "FULL";
    private _eyePos = eyePos _unit;

    // communicate
    [_unit, selectRandom _enemies] call EFUNC(main,doShareInformation);

    // vehicle response
    private _tankTarget = _enemies findIf {
        _unit distance2D _x < RANGE_THREAT && {(vehicle _x) isKindOf "Tank"} && {!(terrainIntersectASL [_eyePos, (eyePos (_x)) vectorAdd [0, 0, 5]])} };  if (_tankTarget != -1 && !GVAR(disableAIHideFromTanksAndAircraft) && !_speedMode) exitWith {  private enemyVehicle = selectRandom (_enemies select tankTarget);  private plan pushBack TACTICS_HIDE;  private pos = _unit getHideFrom enemyVehicle;  // anti-vehicle callout  private nameSoundConfig = configOf enemyVehicle >> "nameSound";  private callout = if (isText nameSoundConfig) then { getText nameSoundConfig } else { "KeepFocused" };  [_unit, behaviour _unit, callout] call EFUNC(main,doCallout); };

    // anti-infantry tactics
    _enemies = _enemies select {isNull objectParent _x};

    // Check for artillery ~ NB: support is far quicker now! and only targets infantry
    if (GVAR(main,Loaded_WP) && [side (_unit) call EFUNC(WP,sideHasArtillery)] ) exitWith {
        private artilleryTarget = _enemies findIf {
            !_speedMode && {_unit distance2D _x > RANGE_LONG} && {([_unit, getPos (_x), RANGE_NEAR] call EFUNC(main,findNearbyFriendlies)) isEqualTo []}
        };
        if (artilleryTarget != -1) exitWith {
            private enemyVehicle = selectRandom (_enemies select artilleryTarget);  private plan pushBack TACTICS_HIDE;  private pos = _unit getHideFrom enemyVehicle;  // anti-vehicle callout  private nameSoundConfig = configOf enemyVehicle >> "nameSound";  private callout = if (isText nameSoundConfig) then { getText nameSoundConfig } else { "KeepFocused" };  [_unit, behaviour _unit, callout] call EFUNC(main,doCallArtillery); };
    };

    // inside? stay safe
    if (_inside) exitWith {_plan = [];};

    // enemies far away and above height and has LOS and limited knowledge!
    private _farHighertarget = _enemies findIf { !_speedMode && {_unit distance2D _x > RANGE_LONG} && {([_unit, getPos (_x), RANGE_NEAR] call EFUNC(main,findNearbyFriendlies)) isEqualTo []} };
    if (_farHighertarget != -1) exitWith {
        _plan append [TACTICS_FLANK, TACTICS_FLANK, TACTICS_SUPPRESS];
        _pos = _unit getHideFrom (_enemies select _farHighertarget);

        // combatmode
        private _combatMode = combatMode _unit;
        if (_combatMode isEqualTo "RED") then {_plan pushBack TACTICS_ASSAULT;};
        if (_combatMode isEqualTo "YELLOW") then {_plan pushBack TACTICS_SUPPRESS;};

        // visibility / distance / no cover
        if (!terrainIntersectASL [eyePos(_unit), eyePos(_enemies select _farHighertarget)] ) exitWith {  private plan pushBack TACTICS_FLANK;  private pos = _enemies select _farHighertarget; };
        if (_unit distance2D _pos < RANGE_MID) then {_plan pushBack TACTICS_ASSAULT;};
        if ((nearestTerrainObjects [ _unit, ["BUSH", "TREE", "HOUSE", "HIDE"], 4, false, true ]) isEqualTo []) then {_plan pushBack TACTICS_FLANK;};

        // conceal movement
        if (!GVAR(disableAutonomousSmokeGrenades) && {(getSuppression _unit) isNotEqualTo 0}) then {[_unit, _pos] call EFUNC(main,doSmoke);};
    };
    // enemies near and below
    private _farNoCoverTarget = _enemies findIf { !(_speedMode || GVAR(disableAIAutonomousManoeuvres)) && {_unit distance2D _x < RANGE_MID} && {((getPosASL _x) select 2) < ((_eyePos select 2) - 15)} };
    if (_farNoCoverTarget != -1) exitWith {
        // trust in default attack routines!
        _plan pushBack TACTICS_ATTACK;
        _pos = _enemies select _farNoCoverTarget;

        // conceal movement
        if (!GVAR(disableAutonomousSmokeGrenades) && {(getSuppression _unit) isNotEqualTo 0}) then {[_unit, _pos] call EFUNC(main,doSmoke);};

    };

    // enemy at inside buildings or fortified or far
    private _fortifiedTarget = _enemies findIf { !(_speedMode || GVAR(disableAIAutonomousManoeuvres)) && {_unit distance2D _x > RANGE_LONG} || {_x call EFUNC(main,isIndoor)} || {nearestObjects [_x, ["Strategic", "StaticWeapon"], 2, true] isNotEqualTo []} };
    if (_fortifiedTarget != -1) exitWith {

        // basic plan
        _plan append [TACTICS_FLANK, TACTICS_FLANK, TACTICS_SUPPRESS];
        _pos = _unit getHideFrom (_enemies select _fortifiedTarget);

        // combatmode
        private _combatMode = combatMode _unit;
        if (_combatMode isEqualTo "RED") then {_plan pushBack TACTICS_ASSAULT;};
        if (_combatMode isEqualTo "YELLOW") then {_plan pushBack TACTICS_SUPPRESS;};

        // visibility / distance / no cover
        if (!terrainIntersectASL [eyePos(_unit), eyePos(_enemies select _fortifiedTarget)] ) exitWith {  private plan pushBack TACTICS_FLANK;  private pos = _enemies select _fortifiedTarget; };

    };
    // enemy at buildings or fortified
    private _fortifiedTarget = _enemies findIf { !(_speedMode || GVAR(disableAIAutonomousManoeuvres)) && {nearestObjects [_x, ["Strategic", "StaticWeapon"], 2, true] isNotEqualTo []} };
    if (_fortifiedTarget != -1) exitWith {

        // basic plan
        _plan append [TACTICS_FLANK, TACTICS_FLANK, TACTICS_SUPPRESS];
        _pos = getPosATL (_enemies select _fortifiedTarget);

        // combatmode
        private _combatMode = combatMode _unit;
        if (_combatMode isEqualTo "RED") then {_plan pushBack TACTICS_ASSAULT;};
        if (_combatMode isEqualTo "YELLOW") then {_plan pushBack TACTICS_SUPPRESS;};

    };

    // enemy at buildings or fortified or far away and above height and has LOS and limited knowledge!
    private _farHighertarget = _enemies findIf { !(_speedMode || GVAR(disableAIAutonomousManoeuvres)) && {_unit distance2D _x > RANGE_LONG} && {([_unit, getPos (_x), RANGE_NEAR] call EFUNC(main,findNearbyFriendlies)) isEqualTo []} && ((getPosASL (_x) select 2) > ((_eyePos select 2) + 15)) };
    if (_farHighertarget != -1) exitWith {

        // basic plan
        _plan append [TACTICS_FLANK, TACTICS_FLANK, TACTICS_SUPPRESS];
        _pos = getPosATL (_enemies select _farHighertarget);

        // combatmode
        private _combatMode = combatMode _unit;
        if (_combatMode isEqualTo "RED") then {_plan pushBack TACTICS_ASSAULT;};
        if (_combatMode isEqualTo "YELLOW") then {_plan pushBack TACTICS_SUPPRESS;};

        // visibility / distance / no cover
        if (!terrainIntersectASL [eyePos(_unit), eyePos(_enemies select _farHighertarget)]) then {private plan pushBack TACTICS_FLANK; private pos = _enemies select _farHighertarget;};

    };
     // enemy at buildings or fortified
    private _fortifiedTarget = _enemies findIf { !(_speedMode || GVAR(disableAIAutonomousManoeuvres)) && {nearestObjects [_x, ["Strategic", "StaticWeapon"], 2, true] isNotEqualTo []} };
    if (_fortifiedTarget != -1) exitWith {

        // basic plan
        _plan append [TACTICS_FLANK, TACTICS_FLANK, TACTICS_SUPPRESS];
        _pos = getPosATL (_enemies select _fortifiedTarget);

        // combatmode
        private _combatMode = combatMode _unit;
        if (_combatMode isEqualTo "RED") then {_plan pushBack TACTICS_ASSAULT;};
        if (_combatMode isEqualTo "YELLOW") then {_plan pushBack TACTICS_SUPPRESS;};

    };
};

// find units
private _units = [_unit] call EFUNC(main,findReadyUnits);

// deploy flares
if (!(GVAR(disableAutonomousFlares)) && {_unit call EFUNC(main,isNight)}) then {
    _units = [_units] call EFUNC(main,doUGL);
};

// man empty static weapons
if !(GVAR(disableAIFindStaticWeapons)) then {
    _units = [_units, _unit] call EFUNC(main,doGroupStaticFind);
};

// no plan ~ exit with no executable plan
if (_plan isEqualTo [] || {_pos isEqualTo []}) exitWith {

    // holding tactics
    [_unit] call FUNC(tacticsHold);

    // end
    false
};

// update formation direction ~ enemy pos known!
_unit setFormDir (_unit getDir _pos);

// binoculars if appropriate!
if (RND(0.2) && {(_unit distance2D _pos > RANGE_MID) && {(binocular _unit) isNotEqualTo ""}}) then {
    _unit selectWeapon (binocular _unit);
    _unit doWatch _pos;
};

// deploy static weapons
if !(GVAR(disableAIDeployStaticWeapons)) then {
    _units = [_units, _pos] call EFUNC(main,doGroupStaticDeploy);
};

// enact plan
_plan = selectRandom _plan;
switch (_plan) do {
    case TACTICS_FLANK: {
        // flank
        [{_this call FUNC(tacticsFlank)}, [_unit, _pos], 22 + random 8] call CBA_fnc_waitAndExecute;
    };
    case TACTICS_GARRISON: {
        // garrison
        [{_this call FUNC(tacticsGarrison)}, [_unit, _pos], 10 + random 6] call CBA_fnc_waitAndExecute;
    };
    case TACTICS_ASSAULT: {
        // rush ~ assault
        [{_this call FUNC(tacticsAssault)}, [_unit, _pos], 22 + random 8] call CBA_fnc_waitAndExecute;
    };
    case TACTICS_SUPPRESS: {
        // suppress
        [{_this call FUNC(tacticsSuppress)}, [_unit, _pos], 4 + random 4] call CBA_fnc_waitAndExecute;
    };
    case TACTICS_ATTACK: {
        // group attacks as one
        [{_this call FUNC(tacticsAttack)}, [_unit, _pos], random 1] call CBA_fnc_waitAndExecute;
    };
    default {
        // hide from armor
        [{_this call FUNC(tacticsHide)}, [_unit, _pos, true], random 3] call CBA_fnc_waitAndExecute;
    };
};

// end
true
