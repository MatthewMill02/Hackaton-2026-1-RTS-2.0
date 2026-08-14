# Automata Tech-War (RTS) — Godot 4 Engine Port

Gra strategiczna czasu rzeczywistego (RTS) dla **4 graczy online / LAN / Radmin VPN**, tworzona w ramach **Hackaton 2026 #1**, przepisywana i rozwijana w silniku **Godot Engine 4**.

---

## 🏛️ Architektura: 100% Czysty Kod (Pure Script GDScript)

Projekt realizowany jest w oparciu o rygorystyczną metodologię programistyczną:
* **Brak wizualnej edycji scen (`.tscn`):** Wszystkie węzły, interfejsy UI, panele, layouty i obiekty gry są tworzone i konfigurowane w 100% proceduralnie w skryptach GDScript.
* **Godot jako silnik renderujący i biblioteka:** Silnik odpowiada za renderowanie grafiki, obsługę wejścia i High-Level Multiplayer, natomiast cała logika i struktura sceny budowana jest ze skryptu głównego [`main.gd`](file:///m:/Projekty/Hackaton%202026/RTS-Godot/rts-hackaton-2026/main.gd).

---

## 🌐 Moduł Sieciowy i Lobby (High-Level Multiplayer)

Gra wykorzystuje wbudowany w Godot 4 system sieciowy `ENetMultiplayerPeer` z procedurami RPC (`@rpc`):

* **Automatyczne Kody Pokoju (6-literowe):**
  * Każdy nowo utworzony pokój otrzymuje unikalny 6-literowy kod (np. `KPRTZQ`).
  * Gracze mogą dołączyć wpisując kod lub kopiując go jednym kliknięciem.
* **Wybór IP Radmin VPN / LAN:**
  * Host ma możliwość automatycznego wykrycia adresu z karty **Radmin VPN** (`26.x.x.x`), karty LAN (`192.168.x.x`) lub wpisania dowolnego własnego IP.
* **Przeglądarka Publicznych Pokoi (Server Browser):**
  * Opcja oznaczenia pokoju jako **Publiczny** (widoczny na liście) lub **Prywatny** (dostępny tylko z kodem).
  * Przeglądarka serwerów w czasie rzeczywistym z przyciskiem **[ 🔄 Odśwież ]** korzystająca z bezkonfiguracyjnego mechanizmu **UDP Discovery** (port `7778`).
* **Interaktywne Lobby:**
  * 4 sloty graczy przypisane do 4 unikalnych pozycji startowych/kolorów baz (Niebieska, Czerwona, Zielona, Żółta).
  * System gotowości (`[GOTOWY]` / `[CZEKA]`), oznaczenie Hosta (`👑`), zintegrowany czat tekstowy i kontrola startu meczu przez Hosta.

---

## 🗺️ Mechaniki Gry (Roadmap / Port z prototypu HTML)

* **Ekonomia 4 Surowców:**
  * Kamień, Żelazo, Ropa, Czerwienit.
* **Power Grid (Sieć Energetyczna):**
  * Bilans produkcji i zużycia energii (kW/s), pylony przesyłowe, baterie magazynujące, blackouty w przypadku przeciążenia.
* **Budynki & Rozbudowa Bazy:**
  * Kwatera Główna (HQ), Kopalnie, Magazyn surowców, Fabryka jednostek, Wieżyczki obronne, Mury, Laboratorium badawcze.
* **Jednostki:**
  * **Dron roboczy:** Zbieranie surowców, budowa i naprawa uszkodzonych struktur.
  * **Scout Bot:** Szybka jednostka rozpoznawcza.
  * **Heavy Bot:** Opancerzona jednostka szturmowa.
  * **Behemoth:** Potężna machina oblężnicza.
* **Talia Kart Badań Technologicznych:**
  * Talia 50 kart i 28 unikalnych efektów/ulepszeń (bonusy do pancerza, ekonomii, prędkości jednostek).
* **PvE i Handel:**
  * Neutralne obozy i bossowie na mapie (drop kart i rzadkich surowców), handel barterowy i kontrakty pasywne.

---

## 📂 Struktura Projektu

```
rts-hackaton-2026/
├── project.godot                     # Konfiguracja silnika (1280x720, canvas_items)
├── export_presets.cfg                # Konfiguracja eksportu (Windows, Linux)
├── main.gd                           # Główny punkt wejścia i zarządca widoków
└── src/
    ├── core/
    │   └── game_state.gd             # Globalne enumy, stałe, kolory slotów
    ├── network/
    │   ├── lobby_discovery.gd        # UDP Beacon Broadcaster / Listener (LAN/Radmin)
    │   ├── network_manager.gd        # ENetMultiplayerPeer, obsługa RPC i sesji
    │   ├── player_data.gd            # Model danych gracza
    │   └── room_code_helper.gd       # Generator i walidator kodów 6-literowych
    └── ui/
        ├── ui_theme.gd               # Programistyczny motyw Cyber / Tech-War
        ├── menu_view.gd              # Menu główne (Host, Kod, Lista serwerów)
        └── lobby_view.gd             # Widok lobby, sloty, czat, gotowość
```

---

## 📦 Automatyczne Buildy (GitHub Actions)

Projekt posiada skonfigurowany workflow CI/CD. Aby automatycznie wygenerować gotowy build produkcyjny i utworzyć Release na GitHubie, wystarczy nadać i wysłać tag wersji:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions automatycznie skompiluje projekt i dołączy paczkę `.zip` z plikiem `.exe` do nowo utworzonego wydania.
