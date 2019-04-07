#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

float fSpawnTime[64];

public Plugin myinfo = 
{
	name = "Bots No Knives",
	author = "TeV / FLWL",
	description = "Stop bots from running with their knives out on round start. Also prevent player from spawning with C4 equipped.",
	version = "1.0"
};

public void OnPluginStart()
{
	HookEvent("player_spawn", EventPlayerSpawn, EventHookMode_Post);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

public Action:OnWeaponSwitch(id, weapon)
{
	float fTimeSinceSpawn = GetGameTime() - fSpawnTime[id];
	
	new String:sWeapon[32];
	GetEdictClassname(weapon, sWeapon, sizeof(sWeapon));
	
	if (!IsFakeClient(id))
	{
		if (StrEqual(sWeapon, "weapon_c4") && fTimeSinceSpawn < 0.1)
		{
			// player tries to switch to c4 on spawn
			return Plugin_Handled;
		}
	}
	else
	{
		if (fTimeSinceSpawn < 5.0 && StrEqual(sWeapon, "weapon_c4") || StrEqual(sWeapon, "weapon_knife"))
		{
			// bot tries to switch to c4/knife shortly after spawning
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action:EventPlayerSpawn(Event event, const char[] name, bool dontBroadcast) 
{
	int id = GetClientOfUserId(GetEventInt(event, "userid"));
	fSpawnTime[id] = GetGameTime();
}
