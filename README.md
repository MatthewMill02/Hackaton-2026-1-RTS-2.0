# Factory of War (RTS) — Godot 4 Engine

Gra strategiczna czasu rzeczywistego (RTS) dla **4 graczy online / LAN / Radmin VPN**, tworzona w ramach **Hackaton 2026 #1** na silniku **Godot Engine 4**.

---

## 🏛️ Architektura: 100% Czysty Kod (Pure Script GDScript)

Projekt realizowany jest w oparciu o czystą architekturę kodową:
* **Brak wizualnej edycji scen (`.tscn`):** Wszystkie węzły, interfejsy UI, panele, layouty, siatka mapy i obiekty gry są tworzone i konfigurowane w 100% proceduralnie w skryptach GDScript.
* **Godot jako silnik renderujący i biblioteka:** Silnik odpowiada za renderowanie grafiki 2D, obsługę wejścia i High-Level Multiplayer, natomiast cała logika i struktura sceny budowana jest ze skryptu głównego [`main.gd`](file:///m:/Projekty/Hackaton%202026/RTS-Godot/rts-hackaton-2026/main.gd).

---

## 🌐 Moduł Sieciowy i Lobby (High-Level Multiplayer)

Gra wykorzystuje system sieciowy `ENetMultiplayerPeer` z procedurami RPC (`@rpc`):

* **Automatyczne Kody Pokoju (6-literowe):**
  * Każdy nowo utworzony pokój otrzymuje unikalny 6-literowy kod (np. `HUJFFC`).
  * Gracze mogą dołączyć wpisując kod lub kopiując go jednym kliknięciem.
* **Wybór IP Radmin VPN / LAN:**
  * Host ma możliwość automatycznego wykrycia adresu z karty **Radmin VPN** (`26.x.x.x`), karty LAN (`192.168.x.x`) lub wpisania dowolnego własnego IP.
* **Przeglądarka Publicznych Pokoi (Server Browser):**
  * Opcja oznaczenia pokoju jako **Publiczny** (widoczny na liście) lub **Prywatny** (dostępny tylko z kodem).
  * Przeglądarka serwerów w czasie rzeczywistym z przyciskiem **[ 🔄 Odśwież ]** korzystająca z mechanizmu **UDP Discovery** (port `7778`).
* **Interaktywne Lobby 70/30:**
  * **Lewa strona:** Podgląd mapy proceduralnej w skali 50x50 kratek. Bezpośrednie kliknięcie na bazę (`B1` Niebieska, `B2` Czerwona, `B3` Zielona, `B4` Żółta) przypisuje gracza do narożnika i koloruje jego nick.
  * **Prawa strona:** Lista graczy, kody, parametry meczu (Tryb kreatywny, Punkty do wygranej, Czas gry) oraz zintegrowany czat tekstowy ze specjalnymi kolorami powiadomień (`SYSTEM`, `USTAWIENIA`, `GRACZ`, `START`).

---

## 🗺️ Mechaniki Rozgrywki (Factory of War)

* **Proceduralna Mapa 50x50:**
  * Siatka 50x50 kratek + 1-kratkowe niegrywalne obramowanie.
  * 4 bazy w narożnikach, losowe skupiska Żelaza i Kamienia w pobliżu baz, Ropa i Czerwienit w drodze do centrum, centralna **Strefa Boss** oraz 4 neutralne **Obozy NPC**.
* **Ekonomia 4 Surowców:**
  * **Kamień:** budowa murów, wieżyczek, pylonów, magazynów.
  * **Żelazo:** budynki produkcyjne, jednostki, **amunicja do wieżyczek** (`-1` żelaza/strzał).
  * **Ropa:** drony, jednostki bojowe, zasilanie elektrowni.
  * **Czerwienit:** wieże laserowe, drony EMP, technologie i zaawansowane akumulatory.
* **Power Grid (Sieć Energetyczna):**
  * Bilans mocy (kW/s): Kwatera Główna (`+50 kW`), Elektrownia (`+100 kW`), pobór standby/active budynków.
  * Banki Energii magazynują nadwyżkę prądu w akumulatorach (kJ). Przy deficycie akumulatory podtrzymują zasilanie, zapobiegając natychmiastowemu blackoutowi.
  * Zasięg zasilania Pylonów i Kwatery Głównej warunkuje możliwość stawiania struktur.
* **Wydobycie Surowców:**
  * **Automatyczne Kopalnie:** Kopalnia Kamienia i Kopalnia Żelaza wydobywają surowce automatycznie co sekundę, gdy są zasilane.
  * **Drony Robocze:** Pętla automatycznego wydobycia (LPM zaznaczenie, PPM na złoże -> kopanie -> znoszenie do bazy -> powrót).
* **System Budowania Snap-to-Grid:**
  * Dynamiczny podgląd (Ghost preview 48px) weryfikujący zasięg zasilania, wolne miejsce i koszt surowców.
  * Tryb wyburzania ze zwrotem 50% zainwestowanych materiałów.
* **Wieżyczki Obronne i Walka:**
  * Wieżyczki automatycznie namierzają cele w promieniu 6 kratek, zużywają amunicję żelaza i generują wiązki laserowe.
  * Zniszczenie Obozów NPC i Bossa nagradza gracza surowcami i odblokowuje losowe Karty Badań.
* **Talia Kart Badań Technologicznych:**
  * Talia unikalnych kart researchu (np. *Głębokie Wiercenia*, *Superkondensatory*, *Włókna Tytanowe*, *Linia Taśmowa*, *Kondensatory Plazmowe*), przyznających globalne modyfikatory.
* **Nakładka TAB & Pop-up ESC:**
  * Przytrzymanie klawisza `TAB` wyświetla ranking, statystyki graczy (PKT, BUD, JDN, ZAB, ZNS) i podsumowanie.
  * Klawisz `ESC` otwiera pop-up ustawień z opcjami pauzy i bezpiecznego opuszczenia meczu.
  * Klawisz `F11` przełącza tryb pełnoekranowy (Fullscreen / Okno).

---

## 📂 Struktura Projektu

```
rts-hackaton-2026/
├── project.godot                     # Konfiguracja silnika (Factory of War, canvas_items)
├── export_presets.cfg                # Konfiguracja eksportu (Windows Desktop)
├── main.gd                           # Główny punkt wejścia, CanvasLayer i orkiestrator
└── src/
    ├── core/
    │   ├── game_state.gd             # Globalne enumy, stałe, kolory slotów
    │   ├── map_data.gd               # Model danych siatki 50x50, zasobów i obozów
    │   ├── map_generator.gd          # Proceduralny generator mapy 50x50
    │   └── settings_manager.gd       # Zapis ustawień (nick, rozdzielczość, F11, IP)
    ├── game/
    │   ├── economy_manager.gd        # Bilans 4 surowców i sieć kW/kJ
    │   ├── building_system.gd        # Definicje struktur, snap to grid, zasilanie
    │   ├── unit_manager.gd           # Drony robocze, pętla wydobycia i jednostki bojowe
    │   ├── combat_system.gd          # Wieżyczki, zużycie amunicji, lasery, obozy PVE
    │   └── research_system.gd        # Baza kart badań technologicznych
    ├── network/
    │   ├── lobby_discovery.gd        # UDP Beacon Broadcaster / Listener (LAN/Radmin)
    │   ├── network_manager.gd        # ENetMultiplayerPeer, obsługa RPC i sesji
    │   ├── player_data.gd            # Model danych gracza
    │   └── room_code_helper.gd       # Generator i walidator kodów 6-literowych
    └── ui/
        ├── ui_theme.gd               # Programistyczny motyw Overwatch / Cyber
        ├── menu_view.gd              # Menu główne (slajdy bannerów, profil)
        ├── lobby_view.gd             # Interaktywne lobby 70/30 z mapą taktyczną
        ├── join_modal.gd             # Pop-up dołączania (kod / lista serwerów)
        ├── settings_modal.gd         # Pop-up ustawień (menu & ESC in-game)
        ├── scoreboard_modal.gd       # Nakładka TAB (ranking i statystyki meczu)
        └── in_game_hud.gd            # HUD rozgrywki, siatka 2D i kontrola jednostek
```

---

## 📦 Automatyczne Buildy (GitHub Actions)

Projekt posiada skonfigurowany workflow CI/CD. Aby automatycznie wygenerować gotowy build produkcyjny i utworzyć Release na GitHubie, wystarczy nadać i wysłać tag wersji:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions automatycznie skompiluje projekt i dołączy paczkę `Factory-of-War-Windows-x86_64.zip` z plikiem `Factory-of-War.exe` do nowo utworzonego wydania.
