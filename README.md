# Matchmaking (lobby → gra)

System party w stylu "FARMHOUSE / CREATE PARTY":

1. Gracz wchodzi na pusty pad (model `Matchmaking1`–`Matchmaking4`) → otwiera się okno **Create Party**: wybór trybu (`NORMAL`, `🔒1 Win`), rozmiar party `- 1 +`, **CREATE** / **BACK**.
2. Nad padem wisi billboard `0/4 · Touch to create a party`, potem `2/4 · NORMAL • Starting in 12s`.
3. Inni gracze wchodzą na pad, żeby **dołączyć** (serwer sprawdza miejsce i wymagane wygrane). Zejście z padu albo **LEAVE** = wyjście z party.
4. Po odliczaniu (20 s, albo 5 s gdy party jest pełne) cała party leci na **prywatny serwer w miejscu gry** (inny świat). Tryb, mapa i gracze trafiają tam przez MemoryStore (zaufane) + TeleportData (zapas).

## Szybka instalacja w Studio (bez Rojo)

W folderze `install/` są gotowe pliki `.rbxmx`. W Studio kliknij prawym na wskazany serwis → **Insert from File...** i wybierz plik:

| Plik | Prawy klik na |
|---|---|
| `LOBBY_ReplicatedStorage_MatchmakingConfig.rbxmx` | ReplicatedStorage (lobby) |
| `LOBBY_ServerScriptService_*.rbxmx` (3 pliki) | ServerScriptService (lobby) |
| `LOBBY_StarterPlayerScripts_MatchmakingClient.rbxmx` | StarterPlayer → StarterPlayerScripts (lobby) |
| `GAME_ServerScriptService_*.rbxmx` (2 pliki) | ServerScriptService (miejsce gry) |

## Pliki

| Plik | Gdzie w Studio | Typ |
|---|---|---|
| `src/lobby/ReplicatedStorage/MatchmakingConfig.lua` | `ReplicatedStorage/MatchmakingConfig` | ModuleScript |
| `src/lobby/ServerScriptService/Matchmaking/init.server.lua` | `ServerScriptService/Matchmaking` | Script |
| `src/lobby/ServerScriptService/Matchmaking/Pad.lua` | `ServerScriptService/Matchmaking/Pad` (dziecko skryptu) | ModuleScript |
| `src/lobby/ServerScriptService/Matchmaking/Teleporter.lua` | `ServerScriptService/Matchmaking/Teleporter` (dziecko skryptu) | ModuleScript |
| `src/lobby/StarterPlayer/StarterPlayerScripts/MatchmakingClient/init.client.lua` | `StarterPlayer/StarterPlayerScripts/MatchmakingClient` | LocalScript |
| `src/lobby/StarterPlayer/StarterPlayerScripts/MatchmakingClient/MatchmakingUI.lua` | `.../MatchmakingClient/MatchmakingUI` (dziecko) | ModuleScript |
| `src/lobby/ServerScriptService/Leaderboards.server.lua` | `ServerScriptService/Leaderboards` | Script |
| `src/shared/PlayerStats.lua` | `ServerScriptService/PlayerStats` — **w lobby i w miejscu gry** | ModuleScript |
| `src/game/ServerScriptService/MatchLoader.server.lua` | **miejsce gry**: `ServerScriptService/MatchLoader` | Script |

Z Rojo: `rojo serve default.project.json` (lobby) i `rojo serve game.project.json` (miejsce gry).

## Konfiguracja (minimum)

1. **Miejsce gry**: w Creator Hub dodaj do tego samego Experience drugie miejsce (Place) i wpisz jego PlaceId w `MatchmakingConfig.GamePlaceId`.
2. **Pady**: modele w Workspace o nazwach `Matchmaking1`…`Matchmaking4` (działa też `Matchmaking 1`, `Matchmaking_1`). Strefą jest część o nazwie `Pad`/`Zone`/`Hitbox`/`Circle`/`Touch` albo z atrybutem `MatchmakingPad = true`; bez tego PrimaryPart lub największa płaska część. W Output zobaczysz `[Matchmaking] Registered ... (zone: X)` — sprawdź, czy wybrało dobrą część.
3. **Wygrane**: domyślnie `leaderstats.Wins` albo atrybut `Wins` na graczu. Inne źródło → podmień `Config.GetWins`.
4. Teleport działa tylko w opublikowanej grze, nie w Studio — tam po odliczaniu zobaczysz komunikat i pad się zresetuje (UI i party przetestujesz w Studio, teleport tylko w opublikowanej grze).

Atrybuty na modelu `MatchmakingN` (opcjonalne) nadpisują config per pad: `MapName`, `MapImage`, `MaxPlayers`, `PlaceId`.

Jeśli model ma już własny BillboardGui z tekstem `0/4`, usuń go — skrypt tworzy `MatchmakingBillboard` sam.

## Tryby

`Config.Modes` — dodaj kolejny wpis, a przycisk pojawi się w oknie automatycznie:

```lua
{ Id = "Nightmare", DisplayName = "NIGHTMARE", RequiredWins = 5, Color = Color3.fromRGB(120, 0, 200) },
```

Wymaganie wygranych sprawdza serwer (przy tworzeniu i dołączaniu), klient tylko pokazuje kłódkę.

## W miejscu gry

`MatchLoader` ustawia atrybuty na `Workspace`: `MatchMode`, `MatchMap`, `MatchPartySize`, `MatchVerified`, `MatchReady`. Nagrody (np. +1 Win) przyznawaj tylko gdy `MatchVerified == true` — TeleportData przechodzi przez klienta i można je podrobić.

Powrót do lobby z dowolnego skryptu serwera:

```lua
game.ServerStorage.ReturnToLobby:Fire()            -- wszyscy
game.ServerStorage.ReturnToLobby:Fire({ player })  -- wybrani
```

## Topka (Leaderboard)

Modele w Workspace o nazwie zaczynającej się od `Leaderboard` lub `Leadboard` dostają planszę w stylu farmy: czerwony nagłówek stodoły z białym obramowaniem, drewniane deski, złoto/srebro/brąz dla top 3, avatar, nick i wynik. Odświeża się co 60 s (licznik na dole planszy).

- **Ekran**: część o nazwie `Board`/`Screen`/`Display`/`Sign`/`Surface` albo z atrybutem `LeaderboardSurface = true`; bez tego największa część modelu. Napis pojawia się na obu dużych ścianach — jeśli jest odwrócony albo na złej ścianie, ustaw na modelu atrybut `Face` (`Front`, `Back`, `Left`, `Right`).
- **Atrybuty modelu (opcjonalne)**: `Stat` (domyślnie `Wins`), `Rows` (domyślnie 10), `Title` (domyślnie `TOP WINS`).
- Jeśli model pochodzi z Toolboxa i ma własne skrypty/SurfaceGui, usuń je — w Output pojawi się ostrzeżenie, co koliduje.

Dane: `PlayerStats` trzyma wygrane w DataStore (`leaderstats.Wins`, z tego korzysta też blokada trybów) i zapisuje je do OrderedDataStore, z którego czyta topka. Każda zmiana to atomowy `UpdateAsync`, więc lobby i serwery gry nie nadpisują sobie wyników.

Wygraną przyznajesz w miejscu gry, gdy gracz wygra mecz:

```lua
game.ServerStorage.AwardWin:Fire(player)
```

Liczy się tylko w zweryfikowanym meczu (`MatchVerified`) i maks. raz na gracza na mecz.

Test w Studio: włącz **Game Settings → Security → Enable Studio Access to API Services**, uruchom Play i w Command Bar (widok serwera):

```lua
require(game.ServerScriptService.PlayerStats).Increment(game.Players:GetPlayers()[1], "Wins", 5)
```

Plansza pokaże wynik przy następnym odświeżeniu (do 60 s).
