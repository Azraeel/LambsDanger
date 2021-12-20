#include "script_component.hpp"
/*
 * Author: nkenny
 * handles responses while engaging
 *
 * Arguments:
 * 0: unit doing the avaluation <OBJECT>
 * 1: type of data <NUMBER>
 * 2: known target <OBJECT>
 *
 * Return Value:
 * number, timeout
 *
 * Example:
 * [bob, 0, angryBob, 100] call lambs_danger_fnc_brainEngage;
 *
 * Public: No
*/

/*
    Engage actions
    0 Enemy detected
    3 Enemy near
    8 CanFire
*/

params ["_unit", ["_type", -1], ["_target", objNull]];

// timeout
private _timeout = time + 0.5;

// ACE3
_unit setVariable ["ace_medical_ai_lastFired", CBA_missionTime];

// check
if (
    isNull _target
    || {_unit knowsAbout _target isEqualTo 0}
    || {(weapons _unit) isEqualTo []}
    || {(combatMode _unit) in ["BLUE", "GREEN"]}
) exitWith {
    _timeout
};

// look at target
if ((_unit knowsAbout _target) isEqualTo 4) then {
    _unit lookAt _target;
};

// distance
private _distance = _unit distance2D _target;

// near, go for CQB
if (
    _distance < GVAR(cqbRange)
    && {_unit checkAIFeature "PATH"}
    && {(vehicle _target) isKindOf "CAManBase"}
    && {_target call EFUNC(main,isAlive)}
) exitWith {
    [_unit, _target] call EFUNC(main,doAssault);

    // If the target is not alive anymore then we need to find a new target.  This can be done by using the function main:findTarget() which will return a new target if there is one.  The function will also set the variable _target to this new target.  If no targets are found then it will return false and we should stop attacking.  

    if (!{_target call EFUNC(main,isAlive)}) {

        // Find a new target and set it as our current target.  We do this by calling main:findTarget().  This function returns true or false depending on whether or not it found a valid target.  

        if ({call EFUNC(main,findTarget)}) exitWith {
            [_unit, _target] call EFUNC(main,doAssault);
        };

        // If no targets are found then we should stop attacking.  This can be done by setting the variable _attack to false.  

        _attack = false;
    } else exitWith {
        [_unit, _target] call EFUNC(main,doAssault);
    };

    // We need to set a timeout so that the function will not run again until after a certain amount of time has passed.  The timeout is set in seconds and it is added to the current time.  So if you want it to run again in 5 seconds then you would use 5 as the value for this variable.  

    _timeout + 4;
};

// set speed
_unit forceSpeed ([-1, 1] select (_type isEqualTo DANGER_CANFIRE));

// far, try to suppress
if (
    _distance < 500
    && {RND(getSuppression _unit)}
    && {_type isEqualTo DANGER_CANFIRE || {RND(0.6) && {_type isEqualTo DANGER_ENEMYDETECTED}}}
) exitWith {

    if (_timeout > 4)  // If the timeout is greater than 4 seconds then we can assume that the AI has suppressed successfully and we can move on to the next target.  Otherwise we will continue suppressing until it succeeds or times out.  

        [_unit, ATLtoASL ((_unit getHideFrom _target) vectorAdd [0, 0, 0.8]), true] call EFUNC(main,doSuppress);

        exitWith {} // Exit with an empty block so that nothing happens after this function finishes executing.  

    else  // If the suppression fails then we need to try again with a new target and reset our timeout counter.  

        [_unit, ATLtoASL ((_unit getHideFrom _target) vectorAdd [0, 0, 0.8]), true] call EFUNC(main,doSuppress);

        _timeout + 4; // Add 4 seconds to the timeout counter.  
};

// end
_timeout
