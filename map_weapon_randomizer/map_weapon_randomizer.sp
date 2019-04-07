#include <sourcemod>
#include <sdktools_functions>
#include <cstrike>
#include <timers>
#include <convars>
#include <sdkhooks>

// pool of weapons that will be randomly chosen from
char WEAPONS_LIST[][][] = {
	{"weapon_ak47",				"1.5"},
	{"weapon_aug",				"1.5"},
	{"weapon_awp",				"0.3"},
	{"weapon_bizon",			"0.4"},
	{"weapon_famas",			"0.7"},
	{"weapon_g3sg1",			"0.1"},
	{"weapon_galilar",			"0.7"},
	{"weapon_m249",				"0.15"},
	{"weapon_m4a1",				"1.5"},
	{"weapon_m4a1_silencer",	"1.5"},
	{"weapon_mac10",			"0.4"},
	{"weapon_mag7",				"0.5"},
	{"weapon_mp7",				"0.4"},
	{"weapon_mp9",				"0.4"},
	{"weapon_negev",			"0.1"},
	{"weapon_nova",				"0.8"},
	{"weapon_p90",				"0.8"},
	{"weapon_sawedoff",			"0.6"},
	{"weapon_scar20",			"0.1"},
	{"weapon_sg556",			"1.5"},
	{"weapon_ssg08",			"0.6"},
	{"weapon_ump45",			"0.5"},
	{"weapon_xm1014",			"0.6"},
	
	{"weapon_glock",			"0.04"},
	{"weapon_elite",			"0.04"},
	{"weapon_p250",				"0.04"},
	{"weapon_tec9",				"0.04"},
	{"weapon_cz75a",			"0.04"},
	{"weapon_deagle",			"0.04"},
	{"weapon_revolver",			"0.04"},
	{"weapon_usp_silencer",		"0.04"},
	{"weapon_hkp2000",			"0.04"},
	{"weapon_fiveseven",		"0.04"}
};
float summedWeaponWeights[sizeof(WEAPONS_LIST)];
float weaponsWeightSum = 0.0;

#define MAX_SPAWN_LOCATIONS 512
Float:ORIGINAL_LOCATIONS[MAX_SPAWN_LOCATIONS][3];
Float:ORIGINAL_ANGLES[MAX_SPAWN_LOCATIONS][3];
new g_NumOriginalLocations;

new g_WeaponParentPropOff;
new g_iFakeClient;
new g_iRandomSeed;

ConVar cvarRandomizeEveryRound;
ConVar cvarRandomizeAfterTime;
ConVar cvarSnapSpawnAngles;
ConVar cvarDebug;

public Plugin myinfo = 
{
	name = "Map Weapon Randomizer",
	author = "TeV / FLWL",
	description = "Automatically replaces weapon spawns on maps with random weapons.",
	version = "1.0"
};

public void OnPluginStart()
{
	initializeWeaponWeights();
	
	cvarRandomizeEveryRound = CreateConVar("mwr_randomize_every_round", "0", "Randomize weapons every round if enabled, otherwise randomize once at the start of the map.");
	cvarRandomizeAfterTime = CreateConVar("mwr_randomize_after_time", "0", "Randomize weapons after given amount of seconds (for example 86400 for 1 day). Set to 0 to disable.");
	cvarSnapSpawnAngles = CreateConVar("mwr_snap_spawn_angles", "1", "Round spawned weapons' angles to the nearest 90 degrees for a more uniform look. Takes effect after a map change.");
	cvarDebug = CreateConVar("mwr_debug", "0", "Enable debug console messages for Map Weapon Randomizer.");
	
	HookEvent("round_start", EventRoundStart, EventHookMode_PostNoCopy);
	
	g_WeaponParentPropOff = FindSendPropInfo("CBaseCombatWeapon", "m_hOwnerEntity");
}

public void initializeWeaponWeights()
{
	weaponsWeightSum = 0.0;
	for (new i = 0; i < sizeof(WEAPONS_LIST); i++)
	{
		float weaponWeight = StringToFloat(WEAPONS_LIST[i][1]);
		weaponsWeightSum += weaponWeight;
		summedWeaponWeights[i] = weaponsWeightSum;
	}
}

public void OnMapStart()
{
	g_iRandomSeed = GetRandomInt(0, 10000 * 10000);
	
	// add one custom pool day spawn
	//ORIGINAL_LOCATIONS[g_NumOriginalLocations] = Float:{383.0, -350.0, -47.0};
	//ORIGINAL_ANGLES[g_NumOriginalLocations] = Float:{0.0, 90.0, 90.0};
	//g_NumOriginalLocations++;
	
	new maxent = GetMaxEntities(), String:weapon[64];
	
	for (new i = GetMaxClients(); i < maxent && g_NumOriginalLocations < MAX_SPAWN_LOCATIONS; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i))
		{
			GetEdictClassname(i, weapon, sizeof(weapon));
			
			if ((StrContains(weapon, "weapon_") != -1 || StrContains(weapon, "item_") != -1) && GetEntDataEnt2(i, g_WeaponParentPropOff) == -1)
			{
				if (StrContains(weapon, "grenade") == -1)
				{
					new Float:Position[3];
					new Float:Angles[3];
					GetEntPropVector(i, Prop_Send, "m_vecOrigin", Position);
					GetEntPropVector(i, Prop_Send, "m_angRotation", Angles);
					
					if (GetConVarBool(cvarSnapSpawnAngles))
					{
						// round angles to nearest 90 degrees
						// this makes the weapons look better on many maps
						for (new j = 0; j < 3; j++)
						{
							Angles[j] = float(RoundFloat(Angles[j] / 90.0) * 90);
						}
					}
					
					ORIGINAL_LOCATIONS[g_NumOriginalLocations] = Position;
					ORIGINAL_ANGLES[g_NumOriginalLocations] = Angles;
					g_NumOriginalLocations++;
					
					if (GetConVarBool(cvarDebug))
						PrintToServer("[Map Weapon Randomizer] Found spawn %d at %f %f %f with angles %f %f %f", g_NumOriginalLocations - 1, Position[0], Position[1], Position[2], Angles[0], Angles[1], Angles[2]);
					
					RemoveEdict(i);
				}
			}
		}
	}
	
	if (GetConVarBool(cvarDebug))
		PrintToServer("[Map Weapon Randomizer] Map started. Loaded %d weapon spawns.", g_NumOriginalLocations);
}

public void OnMapEnd()
{
	g_NumOriginalLocations = 0;
}

public EventRoundStart(Handle:event, const String:name[], bool:dontBroadcast) 
{
	// check if the random seed must be refreshed after a specified amount of time
	if (GetConVarInt(cvarRandomizeAfterTime) > 0)
	{
		g_iRandomSeed = RoundToFloor(float(GetTime()) / float(GetConVarInt(cvarRandomizeAfterTime))) * 100
	}
	
	RemoveAllWeapons();
	
	g_iFakeClient = CreateFakeClient("Weapon Spawner Fake Client");
	
	if (g_iFakeClient)
	{
		SDKHook(g_iFakeClient, SDKHook_WeaponCanUse, OnWeaponCanUse);
		
		if (!GetConVarBool(cvarRandomizeEveryRound))
		{
			SetRandomSeed(g_iRandomSeed);
		}
		
		new j = 0;
		for (new i = 0; i < g_NumOriginalLocations; i++)
		{
			// generate random weight
			float randomWeight = GetRandomFloat(0.0, weaponsWeightSum);
			
			// find the last item whose cumulative weight is below the generated random one
			new randomWeaponIndex = 0;
			for (new k = 0; k < sizeof(WEAPONS_LIST); k++)
			{
				if (summedWeaponWeights[k] > randomWeight)
				{
					break;
				}
				
				randomWeaponIndex = k;
			}
			
			SpawnItem(WEAPONS_LIST[randomWeaponIndex][0], ORIGINAL_LOCATIONS[i], ORIGINAL_ANGLES[i]);
			j++;
		}
		
		if (GetConVarBool(cvarDebug))
			PrintToServer("[Map Weapon Randomizer] Spawned %d/%d weapons.", j, g_NumOriginalLocations);
		
		KickClient(g_iFakeClient);
	}
}

RemoveAllWeapons()
{
	new maxent = GetMaxEntities(), String:weapon[64];
	
	new iRemovedWeapons = 0;
	for (new i = GetMaxClients(); i < maxent; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i))
		{
			GetEdictClassname(i, weapon, sizeof(weapon));
			
			if ((StrContains(weapon, "weapon_") != -1 || StrContains(weapon, "item_") != -1) && GetEntDataEnt2(i, g_WeaponParentPropOff) == -1)
			{
				if (StrContains(weapon, "grenade") == -1)
				{
					RemoveEdict(i);
					iRemovedWeapons++;
				}
			}
		}
	}
	
	if (GetConVarBool(cvarDebug))
		PrintToServer("[Map Weapon Randomizer] Cleaned up %d weapons.", iRemovedWeapons);
}

SpawnItem(char[] ItemName, Float:Position[3], Float:Angles[3])
{
	if (!IsClientConnected(g_iFakeClient))
	{
		PrintToServer("[Map Weapon Randomizer] Spawn failed - no fake client");
		return;
	}
	
	int ItemId = GivePlayerItem(g_iFakeClient, ItemName);
	
	if (ItemId)
	{
		TeleportEntity(ItemId, Position, Angles, NULL_VECTOR);
	}
	else
	{
		PrintToServer("[Map Weapon Randomizer] Spawn failed");
	}
}

public Action:OnWeaponCanUse(client, weapon)
{
    return Plugin_Handled;
}
