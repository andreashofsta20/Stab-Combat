param([string]$LuauPath = '', [string]$TestFilter = '')
$ErrorActionPreference = 'Stop'
$gameTestRoot = Split-Path -Parent $PSScriptRoot
if (-not $LuauPath) { $LuauPath = Join-Path $env:TEMP 'test6-luau-validation/luau.exe' }
if (-not (Test-Path -LiteralPath $LuauPath)) { throw 'Supply -LuauPath with the official Luau CLI executable.' }
$gameTestModules = [ordered]@{
    ProfileSchema = 'src/Modules/ProfileSchema.luau'
    ReceiptArchive = 'src/server/ServicesHandler/ReceiptArchive.luau'
    FoodConfig = 'src/Modules/FoodConfig.luau'
    FoodState = 'src/server/CombatHandler/FoodState.luau'
    FoodService = 'src/server/CombatHandler/FoodService.luau'
    Hotbar = 'src/server/CombatHandler/HandleHotbar.luau'
    FoodClient = 'src/PlayerClient/HandleFood.luau'
    Profiles = 'src/server/DataStore/ProfileManager.luau'
    OnJoined = 'src/server/DataStore/OnJoined.luau'
    StartupConfig = 'src/Modules/StartupConfig.luau'
    StartupLoader = 'src/Modules/StartupLoader.luau'
    StartupService = 'src/server/StartupService.luau'
    StatusSender = 'src/server/Game/PlayerStatusSender.luau'
    StatusClient = 'src/PlayerClient/ChangeStatusMessage.luau'
    MapCatalog = 'src/server/Game/Maps.luau'
    TutorialService = 'src/server/ServicesHandler/TutorialService.luau'
    TutorialClient = 'src/PlayerClient/TutorialHandler.luau'
    AdminPanel = 'src/server/Admin/HandleAdminPanel.luau'
    VIPHandler = 'src/server/ServicesHandler/VIPHandler.luau'
    PlayerHitbox = 'src/server/CombatHandler/PlayerHitbox.luau'
    Purchases = 'src/server/ServicesHandler/PurchaseHandler.luau'
    Quests = 'src/server/ServicesHandler/QuestsHandler.luau'
    QuestsConfig = 'src/Modules/QuestsConfig.luau'
    DailyRewards = 'src/server/ServicesHandler/DailyRewards.luau'
    DailyRewardsConfig = 'src/Modules/DailyRewardsConfig.luau'
    RewardMath = 'src/Modules/RewardMath.luau'
    MapConfig = 'src/Modules/MapConfig.luau'
    KeybindValidation = 'src/Modules/KeybindValidation.luau'
    KeybindServer = 'src/server/DataStore/KeyBindHandler.luau'
    KeybindClient = 'src/PlayerClient/KeyBindClient.luau'
    CameraToggleConfig = 'src/Modules/CameraToggleConfig.luau'
    CameraToggle = 'src/PlayerClient/Modules/FirstPersonToggle.luau'
    MenuCamera = 'src/PlayerClient/Modules/MenuCamera.luau'
    CameraToggleInitialize = 'src/PlayerClient/InitializeFirstPersonToggle.client.luau'
    KnifeInput = 'src/PlayerClient/HandleKnifeCombat.luau'
    MovementState = 'src/Modules/MovementAnimationState.luau'
    SprintState = 'src/Modules/SprintState.luau'
    HoverConfig = 'src/Modules/PlayerHoverConfig.luau'
    Hover = 'src/PlayerClient/PlayerHover.luau'
    RewardStand = 'src/PlayerClient/Modules/RewardStand.luau'
    DailyRewardsClient = 'src/PlayerClient/DailyRewardsHandler.luau'
    QuestsClient = 'src/PlayerClient/QuestsHandlerClient.luau'
    MovementConfig = 'src/Modules/MovementConfig.luau'
    FirstPersonCameraConfig = 'src/Modules/FirstPersonCameraConfig.luau'
    Movement = 'src/PlayerCharacterClient/Animation.client.luau'
    Mobile = 'src/PlayerClient/MobileHandler.luau'
    KnifeConfig = 'src/Modules/KnifeConfig.luau'
    PlayerInfo = 'src/server/ServicesHandler/GetPlayerInfo.luau'
    Leaderboards = 'src/server/DataStore/LeaderboardsHandler.luau'
    Maps = 'src/server/Game/SpawnMap.luau'
    CursorConfig = 'src/Modules/CursorConfig.luau'
    MouseVisibility = 'src/Modules/MouseCursorVisibility.luau'
    Cursor = 'src/PlayerClient/HandleWeaponCursor.luau'
    MainGame = 'src/server/Game/MainGame.luau'
    Modes = 'src/Modules/GameModes.luau'
    GameReward = 'src/server/Game/GameReward.luau'
    MusicConfig = 'src/Modules/MusicConfig.luau'
    Music = 'src/PlayerClient/Modules/MusicController.luau'
    RoundHandler = 'src/server/Game/RoundHandler.luau'
    GameZone = 'src/server/Game/GameZone.luau'
    ZoneConfig = 'src/Modules/ZoneConfig.luau'
    CombatAudioConfig = 'src/Modules/CombatAudioConfig.luau'
    CombatFeedbackConfig = 'src/Modules/CombatFeedbackConfig.luau'
    HitFeedback = 'src/PlayerClient/Modules/HitFeedback.luau'
    KnifeHint = 'src/PlayerClient/Modules/KnifeHint.luau'
    DataConfig = 'src/Modules/DataConfig.luau'
    LeaderboardsClient = 'src/PlayerClient/Leaderboards.luau'
}
$gameTestBundle = [System.Text.StringBuilder]::new()
[void]$gameTestBundle.AppendLine('local nativeTypeof = typeof; local loaders = {}')
foreach ($gameTestEntry in $gameTestModules.GetEnumerator()) {
    [void]$gameTestBundle.AppendLine("loaders.$($gameTestEntry.Key) = function(env)")
    [void]$gameTestBundle.AppendLine('local game, workspace, script, require, Instance = env.game, env.workspace, env.script, env.require, env.Instance')
    [void]$gameTestBundle.AppendLine('local task, os, Enum, Random = env.task, env.os or os, env.Enum, env.Random')
[void]$gameTestBundle.AppendLine('local Vector2, UDim, UDim2, Color3 = env.Vector2, env.UDim, env.UDim2, env.Color3')
    [void]$gameTestBundle.AppendLine('local CFrame = env.CFrame')
    [void]$gameTestBundle.AppendLine('local Vector3, RaycastParams, OverlapParams, TweenInfo = env.Vector3, env.RaycastParams, env.OverlapParams, env.TweenInfo')
    [void]$gameTestBundle.AppendLine('local typeof, warn, print = env.typeof or nativeTypeof, env.warn or function() end, function() end')
    [void]$gameTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $gameTestRoot $gameTestEntry.Value)))
    [void]$gameTestBundle.AppendLine('end')
}
[void]$gameTestBundle.AppendLine('local tests = (function()')
[void]$gameTestBundle.AppendLine([System.IO.File]::ReadAllText((Join-Path $gameTestRoot 'tests/game-systems.spec.luau')))
$filterBytes = [System.Text.Encoding]::UTF8.GetBytes($TestFilter)
$filterExpression = if ($filterBytes.Length -eq 0) { 'nil' } else { 'string.char(' + ($filterBytes -join ',') + ')' }
[void]$gameTestBundle.AppendLine('end)(); tests(function(name, env) return loaders[name](env or {}) end, ' + $filterExpression + ')')
$gameTestFile = Join-Path ([System.IO.Path]::GetTempPath()) ('test6-game-systems-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    [System.IO.File]::WriteAllText($gameTestFile, $gameTestBundle.ToString())
    & $LuauPath $gameTestFile
    if ($LASTEXITCODE -ne 0) { throw 'Game systems tests failed.' }
} finally {
    Remove-Item -LiteralPath $gameTestFile -ErrorAction SilentlyContinue
}
