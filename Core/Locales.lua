--===========================================================================
-- EzWoW - Flight Map
-- Core/Locales.lua : 8-Language Localization Registry & WorldMap Label Resolver
--===========================================================================
local ADDON_NAME, ns = ...
local type, pairs, ipairs, tonumber, tostring, select, pcall = type, pairs, ipairs, tonumber, tostring, select, pcall

local LocaleRegistry = ns.LocaleRegistry or {}
ns.LocaleRegistry = LocaleRegistry

local LOCALES = {
    enUS = {
        TITLE        = "EzWoW - Flight Map",
        CURRENT      = "You are here",
        FARE         = "Fare",
        TIME         = "Time",
        FREE         = "Free",
        COST_UNKNOWN = "Unknown",
        TIME_UNKNOWN = "Not recorded",
        CLICK        = "Click to fly",
        STOPS        = "%d stop(s)",
        UNREACHABLE  = "No connected flight path",
        UNDISCOVERED = "Flight path not discovered",
        HINT         = "Click: fly   Drag: move   Ctrl+Wheel: size",
        ON           = "on",
        OFF          = "off",
        SEC          = "%ds",
        MIN          = "%dm",
        MIN_SEC      = "%dm %ds",
        APPROX       = "~%s",
        TT_TIME      = "Flight time: %s",
        TT_EST       = "Estimated time: %s",
        TT_EST_NOTE  = "The real time is recorded after you fly it once",
        BAR_SOON     = "Arriving",
        BAR_FLYING   = "Flying",
        BAR_ETA      = "arrive %s",
        SETTINGS     = "Settings",
        HEAD_BASIC   = "General",
        HEAD_MAP     = "Map",
        HEAD_FLIGHT  = "In flight",
        OPT_LANG     = "Language",
        LANG_AUTO    = "Auto",
        OPT_ENABLED  = "Use the EzWoW - Flight Map window",
        OPT_SKIP     = "Skip the dialog and open the map directly",
        OPT_SKIP_SUB = "Hold Shift while talking to see the dialog",
        OPT_WORLDMAP = "Show flight masters by faction on the world map",
        OPT_AUTOALIGN = "Auto-align world map button (Bottom-Left Dock)",
        OPT_LABELS   = "Show destination name, cost and time",
        OPT_LABEL_COMPACT = "Short one-line labels (name; time and cost on hover)",
        OPT_CROP     = "Zoom to flight points",
        OPT_ALL      = "Show undiscovered and unconnected points",
        OPT_SCALE    = "Window size",
        OPT_ALPHA    = "Window transparency",
        OPT_FONT     = "Text size",
        OPT_BAR      = "Show remaining flight time bar",
        OPT_BAR_SUB  = "Drag the bar to move it",
        OPT_ALERT    = "Play a sound and flash the taskbar on arrival",
        OPT_SOON     = "Alert shortly before landing",
        OPT_CONFIRM  = "Confirm before flying",
        OPT_LIST     = "Show destination list",
        OPT_LIST_SUB = "Searchable, sortable list with favorites next to the map",
        OPT_PULSE    = "Pulse effect on your location",
        OPT_AUTOSEARCH     = "Type into the search box as soon as the map opens",
        OPT_AUTOSEARCH_SUB = "Movement keys also go into the box while it is active. Press Esc to leave it",
        NO_MONEY     = "Not enough money",
        RECENT       = "Recent",
        TT_RECENT    = "Recently flown from this flight master",
        BAR_STOPS    = "stop %d/%d",
        BAR_STOPS_N  = "%d stop(s)",
        LIST_SEARCH  = "Search destinations",
        LIST_EMPTY   = "No matching destinations",
        LIST_TOGGLE  = "Destination list",
        SORT_NAME    = "Name",
        SORT_TIME    = "Time",
        SORT_FARE    = "Fare",
        FAV_ADD      = "Add to favorites",
        FAV_REMOVE   = "Remove from favorites",
        CONFIRM_TITLE = "Fly to this destination?",
        CONFIRM_FLY = "Fly",
        CONFIRM_CANCEL = "Cancel",
        CONFIRM_CHANGED = "The fare changed. Please confirm again.",
        BTN_DEFAULT  = "Show default flight map",
        BTN_DONATE   = "Donate",
        DONATE_TITLE = "Support EzWoW - Flight Map",
        DONATE_TEXT  = "If this helps you, a coffee would make my day!\nPress Ctrl+C to copy, then paste it into your browser.",
        MSG_RECORDED = "Flight time recorded: %s -> %s",
        MSG_ENABLED  = "EzWoW - Flight Map: %s",
        MSG_SCALE    = "Window size: %d%%",
        MSG_ALPHA    = "Window transparency: %d%%",
        MSG_CROP     = "Zoom to flight points: %s",
        MSG_ALL      = "Show undiscovered and unconnected points: %s",
        MSG_LABELS   = "Name/cost/time labels: %s",
        MSG_LIST     = "Destination list: %s",
        MSG_SKIP     = "Skip flight master dialog: %s",
        MSG_BAR      = "Remaining flight time bar: %s",
        MSG_ALERT    = "Arrival alert: %s",
        MSG_SOON     = "Arriving at %s in about %d sec.",
        MSG_SOON_SET = "Arriving-soon alert: %s (%d sec before landing)",
        MSG_RESET    = "Window position and size reset.",
        MSG_LANG     = "Language set to: %s",
        MSG_ERROR    = "Error, showing the default flight map instead: %s",
        HELP = {
            "/ezfl config  - open settings",
            "/ezfl lang [auto|ko|en|de|fr|es|ru|zhcn|zhtw]  - change UI language",
            "/ezfl season [plain|auto|spring|summer|autumn|winter|parchment]  - map look",
            "/ezfl fx  - toggle the season effects",
            "/ezfl edit [reset]  - move labels by hand (reset: default spots)",
            "/ezfl on | off  - enable/disable EzWoW - Flight Map",
            "/ezfl skip  - toggle skipping the flight master dialog (Shift: show it)",
            "/ezfl labels  - toggle name/cost/time labels on the map",
            "/ezfl list  - toggle the destination list",
            "/ezfl scale 50-120  - window size (%)",
            "/ezfl alpha 0-70  - window transparency (%)",
            "/ezfl bar  - toggle the remaining flight time bar",
            "/ezfl alert  - toggle the arrival alert",
            "/ezfl soon [5-120]  - toggle the arriving-soon alert / set its seconds",
            "/ezfl reset  - reset window position and size",
            "/ezfl donate  - show the donation link",
        },
        WM = {
            title = "EzWoW - Flight Map · Flight Master",
            toggle = "Flight masters",
            move = "Drag to move",
            openSettings = "Left-click: Expand/collapse filter panel\nRight-click: Reset icon position\nDrag: Move icon",
            toggleHelp = "Show or hide flight masters on world and continent maps.",
            alliance = "Alliance", horde = "Horde", neutral = "Neutral",
            unknown = "Unknown faction", undiscovered = "Flight path not discovered",
            enemy = "Opposing faction flight master",
            visit = "Speak to this flight master to fly",
            autoAlign = "Auto-align on map",
        },
    },
    koKR = {
        TITLE        = "EzWoW - Flight Map · 비행 지도",
        CURRENT      = "현재 위치",
        FARE         = "요금",
        TIME         = "시간",
        FREE         = "무료",
        COST_UNKNOWN = "미확인",
        TIME_UNKNOWN = "미측정",
        CLICK        = "클릭하면 비행합니다",
        STOPS        = "경유 %d곳",
        UNREACHABLE  = "연결된 비행 경로 없음",
        UNDISCOVERED = "비행 경로 미발견",
        HINT         = "클릭: 비행   드래그: 창 이동   Ctrl+휠: 크기",
        ON           = "켜짐",
        OFF          = "꺼짐",
        SEC          = "%d초",
        MIN          = "%d분",
        MIN_SEC      = "%d분 %d초",
        APPROX       = "약 %s",
        TT_TIME      = "소요 시간: %s",
        TT_EST       = "예상 시간: %s",
        TT_EST_NOTE  = "한 번 날아가면 실제 시간이 기록됩니다",
        BAR_SOON     = "곧 도착",
        BAR_FLYING   = "비행 중",
        BAR_ETA      = "%s 도착",
        SETTINGS     = "설정",
        HEAD_BASIC   = "기본",
        HEAD_MAP     = "지도 표시",
        HEAD_FLIGHT  = "비행 중",
        OPT_LANG     = "언어 (Language)",
        LANG_AUTO    = "자동",
        OPT_ENABLED  = "전용 비행 지도 사용",
        OPT_SKIP     = "대화창 없이 바로 지도 열기",
        OPT_SKIP_SUB = "Shift를 누른 채 말을 걸면 대화창이 나옵니다",
        OPT_WORLDMAP = "세계지도에 진영별 비행 조련사 표시",
        OPT_AUTOALIGN = "세계지도 하단 버튼 자동 정렬 (좌하단 도킹)",
        OPT_LABELS   = "목적지 이름·요금·시간 표시",
        OPT_LABEL_COMPACT = "이름표 한 줄로 간단히 (이름만, 시간·요금은 마우스를 올리면)",
        OPT_CROP     = "비행 지점 부분만 크게 보기",
        OPT_ALL      = "미발견·미연결 비행 지점도 표시",
        OPT_SCALE    = "창 크기",
        OPT_ALPHA    = "창 투명도",
        OPT_FONT     = "글자 크기",
        OPT_BAR      = "남은 비행 시간 막대 표시",
        OPT_BAR_SUB  = "막대는 드래그해서 옮길 수 있습니다",
        OPT_ALERT    = "도착하면 소리와 작업 표시줄 깜빡임으로 알림",
        OPT_SOON     = "착륙 직전에 미리 알림",
        OPT_CONFIRM  = "비행 전 확인 창 표시",
        OPT_LIST     = "목적지 목록 표시",
        OPT_LIST_SUB = "지도 옆에 검색·정렬·즐겨찾기 목록을 보여줍니다",
        OPT_PULSE    = "현재 위치 파동 효과",
        OPT_AUTOSEARCH     = "지도가 열리면 검색창에 바로 입력",
        OPT_AUTOSEARCH_SUB = "켜면 이동 키도 검색창에 입력됩니다. Esc로 빠져나옵니다",
        NO_MONEY     = "돈이 부족합니다",
        RECENT       = "최근",
        TT_RECENT    = "이 조련사에서 최근에 간 곳",
        BAR_STOPS    = "경유 %d/%d",
        BAR_STOPS_N  = "경유 %d곳",
        LIST_SEARCH  = "목적지 검색",
        LIST_EMPTY   = "찾는 목적지가 없습니다",
        LIST_TOGGLE  = "목적지 목록",
        SORT_NAME    = "이름",
        SORT_TIME    = "시간",
        SORT_FARE    = "요금",
        FAV_ADD      = "즐겨찾기에 추가",
        FAV_REMOVE   = "즐겨찾기에서 빼기",
        CONFIRM_TITLE = "이 목적지로 비행할까요?",
        CONFIRM_FLY = "비행",
        CONFIRM_CANCEL = "취소",
        CONFIRM_CHANGED = "요금이 변경되었습니다. 다시 확인해 주세요.",
        BTN_DEFAULT  = "기본 비행 지도로 보기",
        BTN_DONATE   = "후원하기",
        DONATE_TITLE = "EzWoW - Flight Map 후원",
        DONATE_TEXT  = "도움이 되셨다면 커피 한 잔으로 응원해 주세요!\nCtrl+C로 복사해서 인터넷 주소창에 붙여 넣으면 됩니다.",
        MSG_RECORDED = "비행 시간 기록: %s → %s",
        MSG_ENABLED  = "전용 비행 지도: %s",
        MSG_SCALE    = "창 크기: %d%%",
        MSG_ALPHA    = "창 투명도: %d%%",
        MSG_CROP     = "비행 지점 부분만 확대: %s",
        MSG_ALL      = "미발견·미연결 비행 지점 표시: %s",
        MSG_LABELS   = "지도에 이름·요금·시간 표시: %s",
        MSG_LIST     = "목적지 목록: %s",
        MSG_SKIP     = "비행 조련사 대화창 건너뛰기: %s",
        MSG_BAR      = "남은 비행 시간 막대: %s",
        MSG_ALERT    = "도착 알림: %s",
        MSG_SOON     = "%s에 약 %d초 후 도착합니다.",
        MSG_SOON_SET = "도착 직전 알림: %s (착륙 %d초 전)",
        MSG_RESET    = "창 위치와 크기 초기화했습니다.",
        MSG_LANG     = "언어 설정: %s",
        MSG_ERROR    = "오류가 나서 기본 비행 지도를 표시합니다: %s",
        HELP = {
            "/ezfl config  - 설정 창 열기",
            "/ezfl lang [auto|ko|en|de|fr|es|ru|zhcn|zhtw]  - 언어 변경",
            "/ezfl season [plain|auto|spring|summer|autumn|winter|parchment]  - 지도 모양 바꾸기",
            "/ezfl fx  - 계절 효과 켜기/끄기",
            "/ezfl edit [reset]  - 이름표 위치 직접 옮기기 (reset: 처음 위치로)",
            "/ezfl on | off  - 전용 비행 지도 켜기/끄기",
            "/ezfl skip  - 대화창 건너뛰고 바로 지도 열기 켜기/끄기 (Shift: 대화창 보기)",
            "/ezfl labels  - 지도에 이름·요금·시간 표시 켜기/끄기",
            "/ezfl list  - 목적지 목록 켜기/끄기",
            "/ezfl scale 50~120  - 창 크기(%)",
            "/ezfl alpha 0~70  - 창 투명도(%)",
            "/ezfl bar  - 남은 비행 시간 막대 켜기/끄기",
            "/ezfl alert  - 도착 알림 켜기/끄기",
            "/ezfl soon [5~120]  - 도착 직전 알림 켜기/끄기 · 몇 초 전에 알릴지 설정",
            "/ezfl reset  - 창 위치와 크기 초기화",
            "/ezfl donate  - 후원 주소 보기",
        },
        WM = {
            title = "EzWoW - Flight Map · 비행 조련사",
            toggle = "비행 조련사",
            move = "드래그 이동",
            openSettings = "왼쪽 클릭: 설정 창 펼치기/접기\n오른쪽 클릭: 아이콘 위치 초기화\n드래그: 아이콘 위치 이동",
            toggleHelp = "세계지도와 대륙 지도의 비행 조련사 표시를 켜거나 끕니다.",
            alliance = "얼라이언스", horde = "호드", neutral = "중립(공용)",
            unknown = "진영 미확인", undiscovered = "비행 경로 미발견",
            enemy = "상대 진영 비행 조련사",
            visit = "비행하려면 해당 비행 조련사와 대화하세요",
            autoAlign = "자동 정렬",
        },
    },
    deDE = {
        TITLE        = "EzWoW - Flight Map · Flugkarte",
        CURRENT      = "Aktueller Ort",
        FARE         = "Kosten",
        TIME         = "Zeit",
        FREE         = "Kostenlos",
        COST_UNKNOWN = "Unbekannt",
        TIME_UNKNOWN = "Nicht erfasst",
        CLICK        = "Klicken zum Fliegen",
        STOPS        = "%d Zwischenstopp(s)",
        UNREACHABLE  = "Keine verbundene Flugroute",
        UNDISCOVERED = "Flugpunkt unentdeckt",
        HINT         = "Klick: Fliegen   Ziehen: Bewegen   Strg+Rad: Größe",
        ON           = "an",
        OFF          = "aus",
        SEC          = "%ds",
        MIN          = "%dm",
        MIN_SEC      = "%dm %ds",
        APPROX       = "~%s",
        TT_TIME      = "Flugzeit: %s",
        TT_EST       = "Geschätzte Zeit: %s",
        TT_EST_NOTE  = "Die echte Zeit wird nach dem ersten Flug gespeichert",
        BAR_SOON     = "Ankunft",
        BAR_FLYING   = "Im Flug",
        BAR_ETA      = "Ankunft %s",
        SETTINGS     = "Einstellungen",
        HEAD_BASIC   = "Allgemein",
        HEAD_MAP     = "Karte",
        HEAD_FLIGHT  = "Im Flug",
        OPT_LANG     = "Sprache",
        LANG_AUTO    = "Auto",
        OPT_ENABLED  = "EzWoW - Flight Map Fenster verwenden",
        OPT_SKIP     = "Dialog überspringen und Karte direkt öffnen",
        OPT_SKIP_SUB = "Umschalttaste gedrückt halten, um den Dialog zu sehen",
        OPT_WORLDMAP = "Flugmeister nach Fraktion auf der Weltkarte zeigen",
        OPT_AUTOALIGN = "Weltkarten-Button automatisch ausrichten",
        OPT_LABELS   = "Zielname, Kosten und Flugzeit anzeigen",
        OPT_LABEL_COMPACT = "Kurze einzeilige Beschriftung (Name; Zeit und Kosten beim Überfahren)",
        OPT_CROP     = "Auf Flugpunkte zoomen",
        OPT_ALL      = "Unentdeckte und nicht verbundene Punkte zeigen",
        OPT_SCALE    = "Fenstergröße",
        OPT_ALPHA    = "Fenstertransparenz",
        OPT_FONT     = "Textgröße",
        OPT_BAR      = "Verbleibende Flugzeit-Leiste anzeigen",
        OPT_BAR_SUB  = "Leiste zum Verschieben ziehen",
        OPT_ALERT    = "Ton abspielen und Taskleiste bei Ankunft blinken lassen",
        OPT_CONFIRM  = "Vor dem Abflug bestätigen",
        OPT_LIST     = "Zielliste anzeigen",
        OPT_LIST_SUB = "Such- und sortierbare Liste mit Favoriten neben der Karte",
        OPT_PULSE    = "Pulseffekt am aktuellen Standort",
        OPT_AUTOSEARCH     = "Beim Öffnen sofort ins Suchfeld tippen",
        OPT_AUTOSEARCH_SUB = "Bewegungstasten tippen ins Suchfeld. Drücke Esc zum Verlassen",
        NO_MONEY     = "Nicht genug Gold",
        RECENT       = "Zuletzt",
        TT_RECENT    = "Zuletzt von diesem Flugmeister angeflogen",
        BAR_STOPS    = "Stopp %d/%d",
        BAR_STOPS_N  = "%d Stopp(s)",
        LIST_SEARCH  = "Ziele suchen",
        LIST_EMPTY   = "Keine passenden Ziele",
        LIST_TOGGLE  = "Zielliste",
        SORT_NAME    = "Name",
        SORT_TIME    = "Zeit",
        SORT_FARE    = "Kosten",
        FAV_ADD      = "Zu Favoriten hinzufügen",
        FAV_REMOVE   = "Aus Favoriten entfernen",
        CONFIRM_TITLE = "Zu diesem Ziel fliegen?",
        CONFIRM_FLY = "Fliegen",
        CONFIRM_CANCEL = "Abbrechen",
        CONFIRM_CHANGED = "Die Kosten haben sich geändert. Bitte erneut bestätigen.",
        BTN_DEFAULT  = "Standard-Flugkarte zeigen",
        BTN_DONATE   = "Spenden",
        MSG_LANG     = "Sprache: %s",
        WM = {
            title = "EzWoW - Flight Map · Flugmeister",
            toggle = "Flugmeister",
            move = "Ziehen zum Bewegen",
            openSettings = "Linksklick: Einstellungen ein-/ausklappen\nRechtsklick: Symbolposition zurücksetzen\nZiehen: Symbol verschieben",
            toggleHelp = "Flugmeister auf Welt- und Kontinentkarten ein-/ausblenden.",
            alliance = "Allianz", horde = "Horde", neutral = "Neutral",
            unknown = "Unbekannte Fraktion", undiscovered = "Flugpunkt unentdeckt",
            enemy = "Feindlicher Flugmeister",
            visit = "Sprich mit diesem Flugmeister, um zu fliegen",
            autoAlign = "Auto-Ausrichtung",
        },
    },
    frFR = {
        TITLE        = "EzWoW - Flight Map · Carte des vols",
        CURRENT      = "Vous êtes ici",
        FARE         = "Coût",
        TIME         = "Temps",
        FREE         = "Gratuit",
        COST_UNKNOWN = "Inconnu",
        TIME_UNKNOWN = "Non mesuré",
        CLICK        = "Cliquer pour voler",
        STOPS        = "%d escale(s)",
        UNREACHABLE  = "Aucune route aérienne reliée",
        UNDISCOVERED = "Point de vol non découvert",
        HINT         = "Clic : voler   Glisser : déplacer   Ctrl+Molette : taille",
        ON           = "activé",
        OFF          = "désactivé",
        SEC          = "%ds",
        MIN          = "%dm",
        MIN_SEC      = "%dm %ds",
        APPROX       = "~%s",
        TT_TIME      = "Temps de vol : %s",
        TT_EST       = "Temps estimé : %s",
        TT_EST_NOTE  = "Le temps réel est enregistré après un premier vol",
        BAR_SOON     = "Arrivée",
        BAR_FLYING   = "En vol",
        BAR_ETA      = "arrivée %s",
        SETTINGS     = "Options",
        HEAD_BASIC   = "Général",
        HEAD_MAP     = "Carte",
        HEAD_FLIGHT  = "En vol",
        OPT_LANG     = "Langue",
        LANG_AUTO    = "Auto",
        OPT_ENABLED  = "Utiliser la fenêtre EzWoW - Flight Map",
        OPT_SKIP     = "Ignorer le dialogue et ouvrir la carte directement",
        OPT_SKIP_SUB = "Maintenez Maj en parlant pour voir le dialogue",
        OPT_WORLDMAP = "Afficher les maîtres de vol par faction sur la carte du monde",
        OPT_AUTOALIGN = "Aligner automatiquement le bouton sur la carte du monde",
        OPT_LABELS   = "Afficher le nom, le coût et la durée",
        OPT_LABEL_COMPACT = "Étiquettes courtes sur une ligne (nom ; durée et coût au survol)",
        OPT_CROP     = "Zoomer sur les points de vol",
        OPT_ALL      = "Afficher les points non découverts et non reliés",
        OPT_SCALE    = "Taille de la fenêtre",
        OPT_ALPHA    = "Transparence de la fenêtre",
        OPT_FONT     = "Taille du texte",
        OPT_BAR      = "Afficher la barre de temps de vol restant",
        OPT_BAR_SUB  = "Faites glisser la barre pour la déplacer",
        OPT_ALERT    = "Jouer un son et faire clignoter la barre des tâches à l'arrivée",
        OPT_CONFIRM  = "Confirmer avant de voler",
        OPT_LIST     = "Afficher la liste des destinations",
        OPT_LIST_SUB = "Liste recherchable et triable avec favoris à côté de la carte",
        OPT_PULSE    = "Effet d'onde sur votre position",
        OPT_AUTOSEARCH     = "Saisir dans la recherche dès l'ouverture",
        OPT_AUTOSEARCH_SUB = "Appuyez sur Échap pour quitter le champ de recherche",
        NO_MONEY     = "Pas assez d'argent",
        RECENT       = "Récent",
        TT_RECENT    = "Destination récente depuis ce maître de vol",
        BAR_STOPS    = "escale %d/%d",
        BAR_STOPS_N  = "%d escale(s)",
        LIST_SEARCH  = "Rechercher une destination",
        LIST_EMPTY   = "Aucune destination trouvée",
        LIST_TOGGLE  = "Liste des destinations",
        SORT_NAME    = "Nom",
        SORT_TIME    = "Temps",
        SORT_FARE    = "Coût",
        FAV_ADD      = "Ajouter aux favoris",
        FAV_REMOVE   = "Retirer des favoris",
        CONFIRM_TITLE = "Voler vers cette destination ?",
        CONFIRM_FLY = "Voler",
        CONFIRM_CANCEL = "Annuler",
        CONFIRM_CHANGED = "Le tarif a changé. Veuillez confirmer à nouveau.",
        BTN_DEFAULT  = "Carte de vol par défaut",
        BTN_DONATE   = "Faire un don",
        MSG_LANG     = "Langue : %s",
        WM = {
            title = "EzWoW - Flight Map · Maître de vol",
            toggle = "Maîtres de vol",
            move = "Glisser pour déplacer",
            openSettings = "Clic gauche : Déplier/replier les options\nClic droit : Réinitialiser la position de l'icône\nGlisser : Déplacer l'icône",
            toggleHelp = "Afficher ou masquer les maîtres de vol sur la carte du monde.",
            alliance = "Alliance", horde = "Horde", neutral = "Neutre",
            unknown = "Faction inconnue", undiscovered = "Point de vol non découvert",
            enemy = "Maître de vol ennemi",
            visit = "Parlez à ce maître de vol pour voyager",
            autoAlign = "Alignement auto",
        },
    },
    esES = {
        TITLE        = "EzWoW - Flight Map · Mapa de vuelo",
        CURRENT      = "Estás aquí",
        FARE         = "Coste",
        TIME         = "Tiempo",
        FREE         = "Gratis",
        COST_UNKNOWN = "Desconocido",
        TIME_UNKNOWN = "Sin registrar",
        CLICK        = "Clic para volar",
        STOPS        = "%d escala(s)",
        UNREACHABLE  = "Sin ruta de vuelo conectada",
        UNDISCOVERED = "Ruta de vuelo no descubierta",
        HINT         = "Clic: volar   Arrastrar: mover   Ctrl+Rueda: tamaño",
        ON           = "activo",
        OFF          = "inactivo",
        SEC          = "%ds",
        MIN          = "%dm",
        MIN_SEC      = "%dm %ds",
        APPROX       = "~%s",
        TT_TIME      = "Tiempo de vuelo: %s",
        TT_EST       = "Tiempo estimado: %s",
        TT_EST_NOTE  = "El tiempo real se guarda tras volar una vez",
        BAR_SOON     = "Llegando",
        BAR_FLYING   = "En vuelo",
        BAR_ETA      = "llega %s",
        SETTINGS     = "Ajustes",
        HEAD_BASIC   = "General",
        HEAD_MAP     = "Mapa",
        HEAD_FLIGHT  = "En vuelo",
        OPT_LANG     = "Idioma",
        LANG_AUTO    = "Auto",
        OPT_ENABLED  = "Usar la ventana de EzWoW - Flight Map",
        OPT_SKIP     = "Omitir diálogo y abrir el mapa directamente",
        OPT_SKIP_SUB = "Mantén Mayús al hablar para ver el diálogo",
        OPT_WORLDMAP = "Mostrar maestros de vuelo por facción en el mapa del mundo",
        OPT_AUTOALIGN = "Alinear botón automáticamente en el mapa del mundo",
        OPT_LABELS   = "Mostrar nombre, coste y tiempo del destino",
        OPT_LABEL_COMPACT = "Etiquetas cortas de una línea (nombre; tiempo y coste al pasar el ratón)",
        OPT_CROP     = "Acercar a los puntos de vuelo",
        OPT_ALL      = "Mostrar puntos no descubiertos y no conectados",
        OPT_SCALE    = "Tamaño de ventana",
        OPT_ALPHA    = "Transparencia de ventana",
        OPT_FONT     = "Tamaño de texto",
        OPT_BAR      = "Mostrar barra de tiempo de vuelo restante",
        OPT_BAR_SUB  = "Arrastra la barra para moverla",
        OPT_ALERT    = "Reproducir sonido y parpadear al llegar",
        OPT_CONFIRM  = "Confirmar antes de volar",
        OPT_LIST     = "Mostrar lista de destinos",
        OPT_LIST_SUB = "Lista con búsqueda, orden y favoritos junto al mapa",
        OPT_PULSE    = "Efecto de pulso en tu ubicación",
        OPT_AUTOSEARCH     = "Escribir en el buscador al abrir el mapa",
        OPT_AUTOSEARCH_SUB = "Pulsa Esc para salir del cuadro de búsqueda",
        NO_MONEY     = "No tienes suficiente dinero",
        RECENT       = "Reciente",
        TT_RECENT    = "Último destino desde este maestro de vuelo",
        BAR_STOPS    = "escala %d/%d",
        BAR_STOPS_N  = "%d escala(s)",
        LIST_SEARCH  = "Buscar destinos",
        LIST_EMPTY   = "No hay destinos coincidentes",
        LIST_TOGGLE  = "Lista de destinos",
        SORT_NAME    = "Nombre",
        SORT_TIME    = "Tiempo",
        SORT_FARE    = "Coste",
        FAV_ADD      = "Añadir a favoritos",
        FAV_REMOVE   = "Quitar de favoritos",
        CONFIRM_TITLE = "¿Volar a este destino?",
        CONFIRM_FLY = "Volar",
        CONFIRM_CANCEL = "Cancelar",
        CONFIRM_CHANGED = "El coste ha cambiado. Confirma de nuevo.",
        BTN_DEFAULT  = "Mostrar mapa de vuelo original",
        BTN_DONATE   = "Donar",
        MSG_LANG     = "Idioma: %s",
        WM = {
            title = "EzWoW - Flight Map · Maestro de vuelo",
            toggle = "Maestros de vuelo",
            move = "Arrastrar para mover",
            openSettings = "Clic izq.: Desplegar/plegar ajustes\nClic der.: Restablecer posición del icono\nArrastrar: Mover icono",
            toggleHelp = "Muestra u oculta los maestros de vuelo en el mapa del mundo.",
            alliance = "Alianza", horde = "Horda", neutral = "Neutral",
            unknown = "Facción desconocida", undiscovered = "Ruta no descubierta",
            enemy = "Maestro de vuelo enemigo",
            visit = "Habla con este maestro de vuelo para volar",
            autoAlign = "Alineación auto",
        },
    },
    ruRU = {
        TITLE        = "EzWoW - Flight Map · Карта полётов",
        CURRENT      = "Вы здесь",
        FARE         = "Цена",
        TIME         = "Время",
        FREE         = "Бесплатно",
        COST_UNKNOWN = "Неизвестно",
        TIME_UNKNOWN = "Нет данных",
        CLICK        = "Нажмите для полёта",
        STOPS        = "Пересадок: %d",
        UNREACHABLE  = "Нет связанного маршрута",
        UNDISCOVERED = "Точка полёта не открыта",
        HINT         = "Клик: полёт   Перетащить: окно   Ctrl+Колесо: масштаб",
        ON           = "вкл.",
        OFF          = "выкл.",
        SEC          = "%d сек.",
        MIN          = "%d мин.",
        MIN_SEC      = "%d мин. %d сек.",
        APPROX       = "~%s",
        TT_TIME      = "Время полёта: %s",
        TT_EST       = "Расчётное время: %s",
        TT_EST_NOTE  = "Точное время сохранится после первого полёта",
        BAR_SOON     = "Прибытие",
        BAR_FLYING   = "В полёте",
        BAR_ETA      = "прибытие в %s",
        SETTINGS     = "Настройки",
        HEAD_BASIC   = "Общие",
        HEAD_MAP     = "Карта",
        HEAD_FLIGHT  = "В полёте",
        OPT_LANG     = "Язык",
        LANG_AUTO    = "Авто",
        OPT_ENABLED  = "Использовать окно EzWoW - Flight Map",
        OPT_SKIP     = "Пропускать диалог и сразу открывать карту",
        OPT_SKIP_SUB = "Удерживайте Shift при разговоре, чтобы увидеть диалог",
        OPT_WORLDMAP = "Показывать распорядителей полётов по фракциям на карте мира",
        OPT_AUTOALIGN = "Автовыравнивание кнопки на карте мира",
        OPT_LABELS   = "Показывать название, цену и время",
        OPT_LABEL_COMPACT = "Короткие подписи в одну строку (название; время и цена при наведении)",
        OPT_CROP     = "Приближать к точкам полёта",
        OPT_ALL      = "Показывать неоткрытые и несвязанные точки",
        OPT_SCALE    = "Размер окна",
        OPT_ALPHA    = "Прозрачность окна",
        OPT_FONT     = "Размер шрифта",
        OPT_BAR      = "Показывать полосу оставшегося времени полёта",
        OPT_BAR_SUB  = "Перетащите полосу для перемещения",
        OPT_ALERT    = "Звук и мигание панели задач по прибытии",
        OPT_CONFIRM  = "Подтверждение перед полётом",
        OPT_LIST     = "Показывать список пунктов назначения",
        OPT_LIST_SUB = "Список с поиском, сортировкой и избранным рядом с картой",
        OPT_PULSE    = "Эффект пульсации на вашей позиции",
        OPT_AUTOSEARCH     = "Фокус на поиске при открытии карты",
        OPT_AUTOSEARCH_SUB = "Нажмите Esc, чтобы выйти из поля поиска",
        NO_MONEY     = "Недостаточно золота",
        RECENT       = "Недавнее",
        TT_RECENT    = "Недавний маршрут от этого распорядителя",
        BAR_STOPS    = "пересадка %d/%d",
        BAR_STOPS_N  = "пересадок: %d",
        LIST_SEARCH  = "Поиск пунктов",
        LIST_EMPTY   = "Пункты не найдены",
        LIST_TOGGLE  = "Список пунктов",
        SORT_NAME    = "Имя",
        SORT_TIME    = "Время",
        SORT_FARE    = "Цена",
        FAV_ADD      = "В избранное",
        FAV_REMOVE   = "Убрать из избранного",
        CONFIRM_TITLE = "Отправиться в этот пункт?",
        CONFIRM_FLY = "Лететь",
        CONFIRM_CANCEL = "Отмена",
        CONFIRM_CHANGED = "Цена изменилась. Подтвердите снова.",
        BTN_DEFAULT  = "Стандартная карта полётов",
        BTN_DONATE   = "Поддержать",
        MSG_LANG     = "Язык: %s",
        WM = {
            title = "EzWoW - Flight Map · Распорядитель полётов",
            toggle = "Распорядители полётов",
            move = "Перетащите для перемещения",
            openSettings = "ЛКМ: Развернуть/свернуть настройки\nПКМ: Сбросить позицию значка\nПеретаскивание: Переместить значок",
            toggleHelp = "Показать или скрыть распорядителей полётов на карте мира.",
            alliance = "Альянс", horde = "Орда", neutral = "Нейтральные",
            unknown = "Неизвестная фракция", undiscovered = "Маршрут не открыт",
            enemy = "Враждебный распорядитель полётов",
            visit = "Поговорите с этим распорядителем, чтобы полететь",
            autoAlign = "Автовыравнивание",
        },
    },
    zhCN = {
        TITLE        = "EzWoW - Flight Map · 飞行地图",
        CURRENT      = "当前位置",
        FARE         = "费用",
        TIME         = "时间",
        FREE         = "免费",
        COST_UNKNOWN = "未知",
        TIME_UNKNOWN = "未记录",
        CLICK        = "点击飞行",
        STOPS        = "途经 %d 站",
        UNREACHABLE  = "无相连飞行路线",
        UNDISCOVERED = "飞行点未发现",
        HINT         = "点击：飞行   拖动：移动窗口   Ctrl+滚轮：缩放",
        ON           = "开启",
        OFF          = "关闭",
        SEC          = "%d秒",
        MIN          = "%d分",
        MIN_SEC      = "%d分%d秒",
        APPROX       = "约%s",
        TT_TIME      = "飞行时间：%s",
        TT_EST       = "预计时间：%s",
        TT_EST_NOTE  = "实际飞行一次后将记录准确时间",
        BAR_SOON     = "即将到达",
        BAR_FLYING   = "飞行中",
        BAR_ETA      = "%s 到达",
        SETTINGS     = "设置",
        HEAD_BASIC   = "常规",
        HEAD_MAP     = "地图显示",
        HEAD_FLIGHT  = "飞行中",
        OPT_LANG     = "语言 (Language)",
        LANG_AUTO    = "自动",
        OPT_ENABLED  = "使用 EzWoW - Flight Map 专属飞行地图",
        OPT_SKIP     = "跳过对话直接打开飞行地图",
        OPT_SKIP_SUB = "按住 Shift 对话可查看原始对话窗口",
        OPT_WORLDMAP = "在世界地图上按阵营显示飞行管理员",
        OPT_AUTOALIGN = "世界地图左下角按钮自动对齐",
        OPT_LABELS   = "显示目的地名称、费用与时间",
        OPT_LABEL_COMPACT = "单行简短标签（仅名称，时间和费用悬停显示）",
        OPT_CROP     = "仅放大飞行点区域",
        OPT_ALL      = "显示未发现和未连接的飞行点",
        OPT_SCALE    = "窗口大小",
        OPT_ALPHA    = "窗口透明度",
        OPT_FONT     = "文字大小",
        OPT_BAR      = "显示剩余飞行时间条",
        OPT_BAR_SUB  = "可拖动时间条调整位置",
        OPT_ALERT    = "到达时播放提示音并闪烁任务栏",
        OPT_CONFIRM  = "飞行前显示确认窗口",
        OPT_LIST     = "显示目的地列表",
        OPT_LIST_SUB = "在地图旁显示可搜索、排序与收藏的列表",
        OPT_PULSE    = "当前位置脉冲动画效果",
        OPT_AUTOSEARCH     = "打开地图时自动聚焦搜索框",
        OPT_AUTOSEARCH_SUB = "激活时移动键也会输入到搜索框，按 Esc 退出",
        NO_MONEY     = "金币不足",
        RECENT       = "最近",
        TT_RECENT    = "最近从该飞行管理员出发的目的地",
        BAR_STOPS    = "途经 %d/%d",
        BAR_STOPS_N  = "途经 %d 站",
        LIST_SEARCH  = "搜索目的地",
        LIST_EMPTY   = "无匹配目的地",
        LIST_TOGGLE  = "目的地列表",
        SORT_NAME    = "名称",
        SORT_TIME    = "时间",
        SORT_FARE    = "费用",
        FAV_ADD      = "添加收藏",
        FAV_REMOVE   = "取消收藏",
        CONFIRM_TITLE = "飞往此目的地？",
        CONFIRM_FLY = "飞行",
        CONFIRM_CANCEL = "取消",
        CONFIRM_CHANGED = "费用已变更，请重新确认。",
        BTN_DEFAULT  = "显示默认飞行地图",
        BTN_DONATE   = "赞助支持",
        MSG_LANG     = "语言已设为：%s",
        WM = {
            title = "EzWoW - Flight Map · 飞行管理员",
            toggle = "飞行管理员",
            move = "拖动移动",
            openSettings = "左键点击：展开/收起设置\n右键点击：重置图标位置\n拖动：移动图标",
            toggleHelp = "在世界地图和大陆地图上显示或隐藏飞行管理员。",
            alliance = "联盟", horde = "部落", neutral = "中立",
            unknown = "未知阵营", undiscovered = "飞行路线未发现",
            enemy = "敌对阵营飞行管理员",
            visit = "与该飞行管理员对话即可飞行",
            autoAlign = "自动对齐",
        },
    },
    zhTW = {
        TITLE        = "EzWoW - Flight Map · 飛行地圖",
        CURRENT      = "目前位置",
        FARE         = "費用",
        TIME         = "時間",
        FREE         = "免費",
        COST_UNKNOWN = "未知",
        TIME_UNKNOWN = "未記錄",
        CLICK        = "點擊飛行",
        STOPS        = "途經 %d 站",
        UNREACHABLE  = "無相連飛行路線",
        UNDISCOVERED = "飛行點未發現",
        HINT         = "點擊：飛行   拖曳：移動視窗   Ctrl+滾輪：縮放",
        ON           = "開啟",
        OFF          = "關閉",
        SEC          = "%d秒",
        MIN          = "%d分",
        MIN_SEC      = "%d分%d秒",
        APPROX       = "約%s",
        TT_TIME      = "飛行時間：%s",
        TT_EST       = "預計時間：%s",
        TT_EST_NOTE  = "實際飛行一次後將記錄準確時間",
        BAR_SOON     = "即將到達",
        BAR_FLYING   = "飛行中",
        BAR_ETA      = "%s 到達",
        SETTINGS     = "設定",
        HEAD_BASIC   = "一般",
        HEAD_MAP     = "地圖顯示",
        HEAD_FLIGHT  = "飛行中",
        OPT_LANG     = "語言 (Language)",
        LANG_AUTO    = "自動",
        OPT_ENABLED  = "使用 EzWoW - Flight Map 專屬飛行地圖",
        OPT_SKIP     = "跳過對話直接打開飛行地圖",
        OPT_SKIP_SUB = "按住 Shift 對話可查看原始對話視窗",
        OPT_WORLDMAP = "在世界地圖上依陣營顯示飛行管理員",
        OPT_AUTOALIGN = "世界地圖左下角按鈕自動對齊",
        OPT_LABELS   = "顯示目的地名稱、費用與時間",
        OPT_LABEL_COMPACT = "單行簡短標籤（僅名稱，時間和費用滑鼠停留顯示）",
        OPT_CROP     = "僅放大飛行點區域",
        OPT_ALL      = "顯示未發現與未連接的飛行點",
        OPT_SCALE    = "視窗大小",
        OPT_ALPHA    = "視窗透明度",
        OPT_FONT     = "文字大小",
        OPT_BAR      = "顯示剩餘飛行時間條",
        OPT_BAR_SUB  = "可拖曳時間條調整位置",
        OPT_ALERT    = "到達時播放提示音並閃爍工作列",
        OPT_CONFIRM  = "飛行前顯示確認視窗",
        OPT_LIST     = "顯示目的地清單",
        OPT_LIST_SUB = "在地圖旁顯示可搜尋、排序與收藏的清單",
        OPT_PULSE    = "目前位置脈衝動畫效果",
        OPT_AUTOSEARCH     = "打開地圖時自動聚焦搜尋框",
        OPT_AUTOSEARCH_SUB = "啟用時移動鍵也會輸入到搜尋框，按 Esc 離開",
        NO_MONEY     = "金幣不足",
        RECENT       = "最近",
        TT_RECENT    = "最近從該飛行管理員出發的目的地",
        BAR_STOPS    = "途經 %d/%d",
        BAR_STOPS_N  = "途經 %d 站",
        LIST_SEARCH  = "搜尋目的地",
        LIST_EMPTY   = "無符合目的地",
        LIST_TOGGLE  = "目的地清單",
        SORT_NAME    = "名稱",
        SORT_TIME    = "時間",
        SORT_FARE    = "費用",
        FAV_ADD      = "加入收藏",
        FAV_REMOVE   = "取消收藏",
        CONFIRM_TITLE = "飛往此目的地？",
        CONFIRM_FLY = "飛行",
        CONFIRM_CANCEL = "取消",
        CONFIRM_CHANGED = "費用已變更，請重新確認。",
        BTN_DEFAULT  = "顯示預設飛行地圖",
        BTN_DONATE   = "贊助支持",
        MSG_LANG     = "語言已設為：%s",
        WM = {
            title = "EzWoW - Flight Map · 飛行管理員",
            toggle = "飛行管理員",
            move = "拖曳移動",
            openSettings = "左鍵點擊：展開/收合設定\n右鍵點擊：重置圖示位置\n拖曳：移動圖示",
            toggleHelp = "在世界地圖與大陸地圖上顯示或隱藏飛行管理員。",
            alliance = "聯盟", horde = "部落", neutral = "中立",
            unknown = "未知陣營", undiscovered = "飛行路線未發現",
            enemy = "敵對陣營飛行管理員",
            visit = "與該飛行管理員對話即可飛行",
            autoAlign = "自動對齊",
        },
    },
}
LOCALES.esMX = LOCALES.esES

local CONST_DB

function LocaleRegistry.resolveActiveLocaleKey()
    local userPref = (ns.DB and ns.DB.lang) or (EzWoW_FlightMapDB and EzWoW_FlightMapDB.lang) or (EzWoW_FlightMapDB and EzWoW_FlightMapDB.lang) or "auto"
    if userPref and userPref ~= "auto" and LOCALES[userPref] then
        return userPref
    end
    local clientLoc = GetLocale and GetLocale() or "enUS"
    if LOCALES[clientLoc] then
        return clientLoc
    end
    return "enUS"
end
ns.GetActiveLocaleKey = LocaleRegistry.resolveActiveLocaleKey

local L = setmetatable({}, {
    __index = function(_, k)
        local loc = LOCALES[LocaleRegistry.resolveActiveLocaleKey()] or LOCALES.enUS
        local v = loc[k]
        if v ~= nil then return v end
        return LOCALES.enUS[k]
    end,
})
ns.L = L

function ns.GetWorldMapText()
    local loc = LOCALES[LocaleRegistry.resolveActiveLocaleKey()] or LOCALES.enUS
    local wmVal = loc.WM or LOCALES.enUS.WM
    return setmetatable({}, {
        __index = function(_, k)
            return (wmVal and wmVal[k]) or LOCALES.enUS.WM[k]
        end,
    })
end

ns.LOCALES = LOCALES

ns.LANG_OPTIONS = {
    { key = "auto", label = "Auto" },
    { key = "koKR", label = "한국어" },
    { key = "enUS", label = "EN" },
    { key = "deDE", label = "DE" },
    { key = "frFR", label = "FR" },
    { key = "esES", label = "ES" },
    { key = "ruRU", label = "RU" },
    { key = "zhCN", label = "简中" },
    { key = "zhTW", label = "繁中" },
}

ns.LANG_ALIASES = {
    auto = "auto",
    ko = "koKR", kokr = "koKR", kr = "koKR",
    en = "enUS", enus = "enUS", engb = "enUS",
    de = "deDE", dede = "deDE",
    fr = "frFR", frfr = "frFR",
    es = "esES", eses = "esES", esmx = "esMX",
    ru = "ruRU", ruru = "ruRU",
    zhcn = "zhCN", cn = "zhCN", zh = "zhCN",
    zhtw = "zhTW", tw = "zhTW",
}

local FLIGHT_TIPS_KO = {
    enabled           = "비행 조련사와 대화할 때 블리자드 기본 비행 창 대신 깔끔한 전용 비행 지도 창을 사용합니다.",
    skipGossip        = "퀘스트가 없는 비행 조련사에게 말을 걸면 대화 선택지를 건너뛰고 즉시 비행 지도를 엽니다. (Shift 클릭 시 일반 대화창 표시)",
    confirmFlight     = "비행 지점을 클릭했을 때 즉시 출발하지 않고 요금과 목적지를 다시 확인하는 팝업 창을 띄웁니다.",
    worldMapFlights   = "세계지도(M)와 대륙 지도에 얼라이언스·호드·중립 비행 조련사 위치를 날개 아이콘으로 표시합니다.",
    worldMapAutoAlign = "세계지도 왼쪽 하단 도킹 바에 EzWoW - Flight Map 아이콘을 자동으로 정렬합니다. 끄면 자유롭게 드래그할 수 있습니다.",
    labels            = "전용 비행 지도 위 각 비행 지점 아래에 목적지 이름, 비행 요금, 소요 시간을 직접 표시합니다.",
    crop              = "비행 지점들이 모여 있는 영역만 확대하여 더 크게 보여줍니다.",
    showUnreachable   = "아직 발견하지 못했거나 현재 위치에서 연결되지 않은 비행 지점도 회색 아이콘으로 함께 표시합니다.",
    showList          = "전용 비행 지도 오른쪽에 목적지 검색, 이름·시간·요금 정렬, 즐겨찾기가 가능한 목록 패널을 표시합니다.",
    pulse             = "전용 비행 지도에서 현재 내가 서 있는 출발지 비행 지점에 눈에 띄는 파동 효과를 표시합니다.",
    autoSearch        = "전용 비행 지도가 열리자마자 검색창에 바로 타자를 칠 수 있도록 입력 포커스를 자동으로 맞춥니다.",
    flightBar         = "비행 중 화면에 목적지까지 남은 비행 시간과 경유지 진행 상황을 막대(타이머 바)로 표시합니다.",
    arrivalAlert      = "비행 목적지에 도착했을 때 알림음을 재생하고 윈도우 작업 표시줄 아이콘을 깜빡여 알려줍니다.",
    soonAlert         = "예상 비행 시간을 기준으로 착륙 몇 초 전에 알림음과 채팅 메시지로 알려줍니다. 기본 15초이며 /ezfl soon 숫자 로 바꿀 수 있습니다.",
}

local FLIGHT_TIPS_EN = {
    enabled           = "Uses the dedicated clean EzWoW - Flight Map window instead of the default Blizzard taxi frame.",
    skipGossip        = "Skips the gossip dialog and opens the flight map immediately when speaking to a flight master with no quests. (Hold Shift to view dialog)",
    confirmFlight     = "Shows a confirmation popup with destination and fare before taking a flight.",
    worldMapFlights   = "Displays Alliance, Horde, and Neutral flight master locations on the World Map and continent maps.",
    worldMapAutoAlign = "Automatically aligns the EzWoW - Flight Map button in the bottom-left dock of the World Map. Uncheck to drag freely.",
    labels            = "Displays destination names, flight costs, and durations directly beneath each flight point on the map.",
    crop              = "Zooms in on the region containing flight points for a closer view.",
    showUnreachable   = "Also displays undiscovered or unconnected flight points in grey on the flight map.",
    showList          = "Shows a searchable, sortable destination list with favorites next to the flight map.",
    pulse             = "Shows a pulsing highlight effect on your current flight master location.",
    autoSearch        = "Automatically focuses the search box as soon as the flight map opens.",
    flightBar         = "Displays an in-flight progress bar showing remaining travel time and stops.",
    arrivalAlert      = "Plays an alert sound and flashes the taskbar when your flight arrives.",
    soonAlert         = "Uses the estimated flight time to warn you with a sound and a chat message a few seconds before landing. 15 seconds by default; change it with /ezfl soon <seconds>.",
}

ns.FLIGHT_TIPS_KO = FLIGHT_TIPS_KO
ns.FLIGHT_TIPS_EN = FLIGHT_TIPS_EN

-- Additional translations for interface messages.
LOCALES.deDE["DONATE_TITLE"] = "EzWoW - Flight Map unterstützen"
LOCALES.frFR["DONATE_TITLE"] = "Soutenir EzWoW - Flight Map"
LOCALES.esES["DONATE_TITLE"] = "Apoyar EzWoW - Flight Map"
LOCALES.ruRU["DONATE_TITLE"] = "Поддержать EzWoW - Flight Map"
LOCALES.zhCN["DONATE_TITLE"] = "支持EzWoW - Flight Map"
LOCALES.zhTW["DONATE_TITLE"] = "支持EzWoW - Flight Map"
LOCALES.deDE["MSG_LABELS"] = "Name-/Kosten-/Zeitanzeige: %s"
LOCALES.frFR["MSG_LABELS"] = "Noms, coûts et durées : %s"
LOCALES.esES["MSG_LABELS"] = "Nombres, costes y tiempos: %s"
LOCALES.ruRU["MSG_LABELS"] = "Названия, стоимость и время: %s"
LOCALES.zhCN["MSG_LABELS"] = "名称、费用和时间标签：%s"
LOCALES.zhTW["MSG_LABELS"] = "名稱、費用與時間標籤：%s"
LOCALES.deDE["MSG_SKIP"] = "Dialog mit Flugmeister überspringen: %s"
LOCALES.frFR["MSG_SKIP"] = "Ignorer le dialogue du maître de vol : %s"
LOCALES.esES["MSG_SKIP"] = "Omitir diálogo del maestro de vuelo: %s"
LOCALES.ruRU["MSG_SKIP"] = "Пропуск диалога распорядителя полётов: %s"
LOCALES.zhCN["MSG_SKIP"] = "跳过飞行管理员对话：%s"
LOCALES.zhTW["MSG_SKIP"] = "略過飛行管理員對話：%s"
LOCALES.deDE["MSG_SCALE"] = "Fenstergröße: %d%%"
LOCALES.frFR["MSG_SCALE"] = "Taille de la fenêtre : %d%%"
LOCALES.esES["MSG_SCALE"] = "Tamaño de ventana: %d%%"
LOCALES.ruRU["MSG_SCALE"] = "Размер окна: %d%%"
LOCALES.zhCN["MSG_SCALE"] = "窗口大小：%d%%"
LOCALES.zhTW["MSG_SCALE"] = "視窗大小：%d%%"
LOCALES.deDE["MSG_ERROR"] = "Fehler, Standardflugkarte wird angezeigt: %s"
LOCALES.frFR["MSG_ERROR"] = "Erreur, affichage de la carte de vol par défaut : %s"
LOCALES.esES["MSG_ERROR"] = "Error, se muestra el mapa de vuelo predeterminado: %s"
LOCALES.ruRU["MSG_ERROR"] = "Ошибка, открыта стандартная карта полётов: %s"
LOCALES.zhCN["MSG_ERROR"] = "发生错误，改用默认飞行地图：%s"
LOCALES.zhTW["MSG_ERROR"] = "發生錯誤，改用預設飛行地圖：%s"
LOCALES.deDE["MSG_BAR"] = "Leiste für verbleibende Flugzeit: %s"
LOCALES.frFR["MSG_BAR"] = "Barre de temps de vol restant : %s"
LOCALES.esES["MSG_BAR"] = "Barra de tiempo de vuelo restante: %s"
LOCALES.ruRU["MSG_BAR"] = "Полоса оставшегося времени полёта: %s"
LOCALES.zhCN["MSG_BAR"] = "剩余飞行时间条：%s"
LOCALES.zhTW["MSG_BAR"] = "剩餘飛行時間條：%s"
LOCALES.deDE["MSG_RESET"] = "Fensterposition und -größe zurückgesetzt."
LOCALES.frFR["MSG_RESET"] = "Position et taille de la fenêtre réinitialisées."
LOCALES.esES["MSG_RESET"] = "Posición y tamaño de ventana restablecidos."
LOCALES.ruRU["MSG_RESET"] = "Положение и размер окна сброшены."
LOCALES.zhCN["MSG_RESET"] = "已重置窗口位置和大小。"
LOCALES.zhTW["MSG_RESET"] = "已重置視窗位置與大小。"
LOCALES.deDE["MSG_LIST"] = "Zielliste: %s"
LOCALES.frFR["MSG_LIST"] = "Liste des destinations : %s"
LOCALES.esES["MSG_LIST"] = "Lista de destinos: %s"
LOCALES.ruRU["MSG_LIST"] = "Список пунктов назначения: %s"
LOCALES.zhCN["MSG_LIST"] = "目的地列表：%s"
LOCALES.zhTW["MSG_LIST"] = "目的地清單：%s"
LOCALES.deDE["OPT_SOON"] = "Kurz vor der Landung warnen"
LOCALES.frFR["OPT_SOON"] = "Prévenir peu avant l'atterrissage"
LOCALES.esES["OPT_SOON"] = "Avisar poco antes de aterrizar"
LOCALES.ruRU["OPT_SOON"] = "Предупреждать незадолго до посадки"
LOCALES.zhCN["OPT_SOON"] = "即将降落时提前提醒"
LOCALES.zhTW["OPT_SOON"] = "即將降落時提前提醒"
LOCALES.deDE["MSG_SOON"] = "Ankunft in %s in etwa %d Sek."
LOCALES.frFR["MSG_SOON"] = "Arrivée à %s dans environ %d s."
LOCALES.esES["MSG_SOON"] = "Llegada a %s en unos %d s."
LOCALES.ruRU["MSG_SOON"] = "Прибытие в %s примерно через %d с."
LOCALES.zhCN["MSG_SOON"] = "%s：约 %d 秒后到达。"
LOCALES.zhTW["MSG_SOON"] = "%s：約 %d 秒後抵達。"
LOCALES.deDE["MSG_SOON_SET"] = "Warnung vor der Landung: %s (%d Sek. vorher)"
LOCALES.frFR["MSG_SOON_SET"] = "Alerte avant l'atterrissage : %s (%d s avant)"
LOCALES.esES["MSG_SOON_SET"] = "Aviso antes de aterrizar: %s (%d s antes)"
LOCALES.ruRU["MSG_SOON_SET"] = "Предупреждение перед посадкой: %s (за %d с)"
LOCALES.zhCN["MSG_SOON_SET"] = "降落前提醒：%s（提前 %d 秒）"
LOCALES.zhTW["MSG_SOON_SET"] = "降落前提醒：%s（提前 %d 秒）"
LOCALES.deDE["MSG_ALERT"] = "Ankunftsmeldung: %s"
LOCALES.frFR["MSG_ALERT"] = "Alerte d'arrivée : %s"
LOCALES.esES["MSG_ALERT"] = "Aviso de llegada: %s"
LOCALES.ruRU["MSG_ALERT"] = "Оповещение о прибытии: %s"
LOCALES.zhCN["MSG_ALERT"] = "到达提醒：%s"
LOCALES.zhTW["MSG_ALERT"] = "抵達提醒：%s"
LOCALES.deDE["MSG_ALL"] = "Unentdeckte und nicht verbundene Punkte anzeigen: %s"
LOCALES.frFR["MSG_ALL"] = "Afficher les points inconnus et non reliés : %s"
LOCALES.esES["MSG_ALL"] = "Mostrar puntos no descubiertos y sin conexión: %s"
LOCALES.ruRU["MSG_ALL"] = "Показывать неоткрытые и несвязанные точки: %s"
LOCALES.zhCN["MSG_ALL"] = "显示未发现和未连接的飞行点：%s"
LOCALES.zhTW["MSG_ALL"] = "顯示未發現與未連接的飛行點：%s"
LOCALES.deDE["MSG_ENABLED"] = "EzWoW - Flight Map: %s"
LOCALES.frFR["MSG_ENABLED"] = "EzWoW - Flight Map : %s"
LOCALES.esES["MSG_ENABLED"] = "EzWoW - Flight Map: %s"
LOCALES.ruRU["MSG_ENABLED"] = "EzWoW - Flight Map: %s"
LOCALES.zhCN["MSG_ENABLED"] = "EzWoW - Flight Map：%s"
LOCALES.zhTW["MSG_ENABLED"] = "EzWoW - Flight Map：%s"
LOCALES.deDE["MSG_ALPHA"] = "Fensterdeckkraft: %d%%"
LOCALES.frFR["MSG_ALPHA"] = "Opacité de la fenêtre : %d%%"
LOCALES.esES["MSG_ALPHA"] = "Opacidad de ventana: %d%%"
LOCALES.ruRU["MSG_ALPHA"] = "Непрозрачность окна: %d%%"
LOCALES.zhCN["MSG_ALPHA"] = "窗口不透明度：%d%%"
LOCALES.zhTW["MSG_ALPHA"] = "視窗不透明度：%d%%"
LOCALES.deDE["DONATE_TEXT"] = "Wenn dir dieses Addon hilft, freue ich mich über einen Kaffee!\nMit Strg+C kopieren und im Browser einfügen."
LOCALES.frFR["DONATE_TEXT"] = "Si cet addon vous aide, vous pouvez m'offrir un café !\nCopiez avec Ctrl+C puis collez dans votre navigateur."
LOCALES.esES["DONATE_TEXT"] = "Si este addon te ayuda, ¡puedes invitarme a un café!\nCopia con Ctrl+C y pega en tu navegador."
LOCALES.ruRU["DONATE_TEXT"] = "Если аддон вам полезен, можно поддержать автора чашкой кофе!\nСкопируйте ссылку с помощью Ctrl+C и вставьте в браузер."
LOCALES.zhCN["DONATE_TEXT"] = "如果这个插件对你有帮助，欢迎请作者喝杯咖啡！\n按Ctrl+C复制，然后粘贴到浏览器中。"
LOCALES.zhTW["DONATE_TEXT"] = "如果這個插件對你有幫助，歡迎請作者喝杯咖啡！\n按Ctrl+C複製，然後貼到瀏覽器中。"
LOCALES.deDE["MSG_CROP"] = "Auf Flugpunkte zoomen: %s"
LOCALES.frFR["MSG_CROP"] = "Zoom sur les points de vol : %s"
LOCALES.esES["MSG_CROP"] = "Ampliar a los puntos de vuelo: %s"
LOCALES.ruRU["MSG_CROP"] = "Масштабирование по точкам полёта: %s"
LOCALES.zhCN["MSG_CROP"] = "缩放至飞行点区域：%s"
LOCALES.zhTW["MSG_CROP"] = "縮放至飛行點區域：%s"
LOCALES.deDE["MSG_RECORDED"] = "Flugzeit aufgezeichnet: %s -> %s"
LOCALES.frFR["MSG_RECORDED"] = "Temps de vol enregistré : %s -> %s"
LOCALES.esES["MSG_RECORDED"] = "Tiempo de vuelo registrado: %s -> %s"
LOCALES.ruRU["MSG_RECORDED"] = "Время полёта записано: %s -> %s"
LOCALES.zhCN["MSG_RECORDED"] = "已记录飞行时间：%s -> %s"
LOCALES.zhTW["MSG_RECORDED"] = "已記錄飛行時間：%s -> %s"

-- Option tooltips for the other six languages (Korean and English are above)
local FLIGHT_TIPS_OTHER = {
    deDE = {
        enabled = "Nutzt das eigene Fenster von EzWoW - Flight Map statt der Standard-Flugkarte.",
        skipGossip = "Überspringt den Dialog und öffnet die Flugkarte sofort, wenn der Flugmeister keine Quests hat. (Umschalt halten, um den Dialog zu sehen)",
        confirmFlight = "Zeigt vor dem Abflug eine Bestätigung mit Ziel und Preis.",
        worldMapFlights = "Zeigt Flugmeister der Allianz, der Horde und neutrale auf Welt- und Kontinentkarte.",
        worldMapAutoAlign = "Richtet den Knopf von EzWoW - Flight Map automatisch unten links auf der Weltkarte aus. Deaktivieren, um ihn frei zu ziehen.",
        labels = "Zeigt Zielname, Flugkosten und Dauer direkt unter jedem Flugpunkt.",
        crop = "Vergrößert den Bereich mit den Flugpunkten für eine nähere Ansicht.",
        showUnreachable = "Zeigt auch unentdeckte oder nicht verbundene Flugpunkte grau an.",
        showList = "Zeigt neben der Karte eine durchsuchbare, sortierbare Zielliste mit Favoriten.",
        pulse = "Hebt deinen aktuellen Flugpunkt pulsierend hervor.",
        autoSearch = "Setzt beim Öffnen der Flugkarte sofort den Cursor ins Suchfeld.",
        flightBar = "Zeigt während des Flugs einen Balken mit Restzeit und Zwischenstopps.",
        arrivalAlert = "Spielt bei der Ankunft einen Ton und lässt die Taskleiste blinken.",
        soonAlert = "Warnt anhand der geschätzten Flugzeit einige Sekunden vor der Landung mit Ton und Chatmeldung. Standard 15 Sek., ändern mit /ezfl soon <Sekunden>.",
    },
    frFR = {
        enabled = "Utilise la fenêtre dédiée EzWoW - Flight Map au lieu de la carte de vol par défaut.",
        skipGossip = "Ignore le dialogue et ouvre directement la carte quand le maître de vol n'a pas de quête. (Maintenez Maj pour voir le dialogue)",
        confirmFlight = "Affiche une confirmation avec la destination et le prix avant le départ.",
        worldMapFlights = "Affiche les maîtres de vol de l'Alliance, de la Horde et neutres sur les cartes du monde et des continents.",
        worldMapAutoAlign = "Aligne automatiquement le bouton EzWoW - Flight Map en bas à gauche de la carte du monde. Décochez pour le déplacer librement.",
        labels = "Affiche le nom, le prix et la durée sous chaque point de vol.",
        crop = "Zoome sur la zone qui contient les points de vol.",
        showUnreachable = "Affiche aussi en gris les points de vol non découverts ou non reliés.",
        showList = "Affiche à côté de la carte une liste de destinations avec recherche, tri et favoris.",
        pulse = "Met en évidence votre point de vol actuel avec un effet pulsé.",
        autoSearch = "Place le curseur dans la recherche dès l'ouverture de la carte.",
        flightBar = "Affiche pendant le vol une barre avec le temps restant et les escales.",
        arrivalAlert = "Joue un son et fait clignoter la barre des tâches à l'arrivée.",
        soonAlert = "D'après la durée estimée, prévient par un son et un message quelques secondes avant l'atterrissage. 15 s par défaut, modifiable avec /ezfl soon <secondes>.",
    },
    esES = {
        enabled = "Usa la ventana propia de EzWoW - Flight Map en lugar del mapa de vuelo predeterminado.",
        skipGossip = "Omite el diálogo y abre el mapa al instante si el maestro de vuelo no tiene misiones. (Mantén Mayús para ver el diálogo)",
        confirmFlight = "Muestra una confirmación con el destino y el precio antes de volar.",
        worldMapFlights = "Muestra los maestros de vuelo de la Alianza, la Horda y neutrales en el mapa del mundo y de los continentes.",
        worldMapAutoAlign = "Alinea automáticamente el botón de EzWoW - Flight Map abajo a la izquierda del mapa del mundo. Desmárcalo para moverlo libremente.",
        labels = "Muestra el nombre, el precio y la duración bajo cada punto de vuelo.",
        crop = "Amplía la zona que contiene los puntos de vuelo.",
        showUnreachable = "Muestra también en gris los puntos de vuelo no descubiertos o sin conexión.",
        showList = "Muestra junto al mapa una lista de destinos con búsqueda, orden y favoritos.",
        pulse = "Resalta con un pulso tu punto de vuelo actual.",
        autoSearch = "Coloca el cursor en la búsqueda nada más abrir el mapa.",
        flightBar = "Muestra durante el vuelo una barra con el tiempo restante y las paradas.",
        arrivalAlert = "Reproduce un sonido y hace parpadear la barra de tareas al llegar.",
        soonAlert = "Según el tiempo estimado, avisa con un sonido y un mensaje unos segundos antes de aterrizar. 15 s por defecto; cámbialo con /ezfl soon <segundos>.",
    },
    ruRU = {
        enabled = "Использует отдельное окно EzWoW - Flight Map вместо стандартной карты полётов.",
        skipGossip = "Пропускает диалог и сразу открывает карту, если у распорядителя полётов нет заданий. (Удерживайте Shift, чтобы увидеть диалог)",
        confirmFlight = "Перед вылетом показывает подтверждение с пунктом назначения и ценой.",
        worldMapFlights = "Показывает распорядителей полётов Альянса, Орды и нейтральных на карте мира и континентов.",
        worldMapAutoAlign = "Автоматически ставит кнопку EzWoW - Flight Map в левый нижний угол карты мира. Снимите флажок, чтобы перемещать её свободно.",
        labels = "Показывает название, стоимость и время полёта под каждой точкой.",
        crop = "Приближает область с точками полёта.",
        showUnreachable = "Также показывает серым неоткрытые или несвязанные точки полёта.",
        showList = "Показывает рядом с картой список пунктов с поиском, сортировкой и избранным.",
        pulse = "Подсвечивает пульсацией вашу текущую точку полёта.",
        autoSearch = "Сразу ставит курсор в поле поиска при открытии карты.",
        flightBar = "Во время полёта показывает полосу с оставшимся временем и остановками.",
        arrivalAlert = "При прибытии проигрывает звук и мигает панелью задач.",
        soonAlert = "По расчётному времени полёта предупреждает звуком и сообщением в чате за несколько секунд до посадки. По умолчанию 15 с; изменить: /ezfl soon <секунды>.",
    },
    zhCN = {
        enabled = "使用 EzWoW - Flight Map 专用窗口代替默认飞行地图。",
        skipGossip = "飞行管理员没有任务时跳过对话，直接打开飞行地图。（按住 Shift 可查看对话）",
        confirmFlight = "起飞前显示包含目的地和费用的确认窗口。",
        worldMapFlights = "在世界地图和大陆地图上显示联盟、部落和中立飞行管理员。",
        worldMapAutoAlign = "自动将 EzWoW - Flight Map 按钮排列在世界地图左下角。取消勾选可自由拖动。",
        labels = "在每个飞行点下方直接显示目的地名称、费用和时间。",
        crop = "放大显示包含飞行点的区域。",
        showUnreachable = "也以灰色显示尚未发现或无法连通的飞行点。",
        showList = "在地图旁显示可搜索、可排序并支持收藏的目的地列表。",
        pulse = "以脉动效果突出显示当前所在的飞行点。",
        autoSearch = "打开飞行地图时自动聚焦搜索框。",
        flightBar = "飞行中显示剩余时间和经停点的进度条。",
        arrivalAlert = "到达时播放提示音并闪烁任务栏。",
        soonAlert = "根据预计飞行时间，在降落前几秒用提示音和聊天消息提醒。默认 15 秒，可用 /ezfl soon <秒数> 修改。",
    },
    zhTW = {
        enabled = "使用 EzWoW - Flight Map 專用視窗取代預設飛行地圖。",
        skipGossip = "飛行管理員沒有任務時跳過對話，直接開啟飛行地圖。（按住 Shift 可查看對話）",
        confirmFlight = "起飛前顯示包含目的地和費用的確認視窗。",
        worldMapFlights = "在世界地圖和大陸地圖上顯示聯盟、部落和中立飛行管理員。",
        worldMapAutoAlign = "自動將 EzWoW - Flight Map 按鈕排列在世界地圖左下角。取消勾選可自由拖曳。",
        labels = "在每個飛行點下方直接顯示目的地名稱、費用和時間。",
        crop = "放大顯示包含飛行點的區域。",
        showUnreachable = "也以灰色顯示尚未發現或無法連通的飛行點。",
        showList = "在地圖旁顯示可搜尋、可排序並支援收藏的目的地清單。",
        pulse = "以脈動效果突顯目前所在的飛行點。",
        autoSearch = "開啟飛行地圖時自動聚焦搜尋框。",
        flightBar = "飛行中顯示剩餘時間和經停點的進度條。",
        arrivalAlert = "抵達時播放提示音並閃爍工作列。",
        soonAlert = "根據預計飛行時間，在降落前幾秒以提示音和聊天訊息提醒。預設 15 秒，可用 /ezfl soon <秒數> 修改。",
    },
}
FLIGHT_TIPS_OTHER.esMX = FLIGHT_TIPS_OTHER.esES
ns.FLIGHT_TIPS_OTHER = FLIGHT_TIPS_OTHER

-- World map style, zone names, quest and dungeon markers
LOCALES.enUS["OPT_WORLDART"] = "Continent map with zone borders (off: flight master map)"
LOCALES.enUS["OPT_ZONENAMES"] = "Zone names and zone highlight"
LOCALES.enUS["OPT_QUESTMARKS"] = "Show quest turn-ins (quest log)"
LOCALES.enUS["OPT_DUNGEONMARKS"] = "Show dungeon entrances"
LOCALES.enUS["MARK_LEVELS"] = "Level %s"
LOCALES.enUS["MARK_TURNIN"] = "Quest turn-in"
LOCALES.enUS["MARK_DONE"] = "ready"
LOCALES.enUS["MARK_NEAREST"] = "Nearest flight point: %s"
LOCALES.enUS["MARK_CLICK"] = "Click: select it in the list"
LOCALES.koKR["OPT_WORLDART"] = "구역 경계가 보이는 대륙 지도 (끄면 비행 조련사 지도)"
LOCALES.koKR["OPT_ZONENAMES"] = "구역 이름과 구역 강조 표시"
LOCALES.koKR["OPT_QUESTMARKS"] = "퀘스트 보고 위치 표시 (퀘스트 목록)"
LOCALES.koKR["OPT_DUNGEONMARKS"] = "던전 입구 표시"
LOCALES.koKR["MARK_LEVELS"] = "레벨 %s"
LOCALES.koKR["MARK_TURNIN"] = "퀘스트 보고"
LOCALES.koKR["MARK_DONE"] = "완료"
LOCALES.koKR["MARK_NEAREST"] = "가까운 비행 지점: %s"
LOCALES.koKR["MARK_CLICK"] = "클릭: 목록에서 선택"
LOCALES.deDE["OPT_WORLDART"] = "Kontinentkarte mit Zonengrenzen (aus: Flugmeisterkarte)"
LOCALES.deDE["OPT_ZONENAMES"] = "Zonennamen und Zonenhervorhebung"
LOCALES.deDE["OPT_QUESTMARKS"] = "Questabgaben anzeigen (Questlog)"
LOCALES.deDE["OPT_DUNGEONMARKS"] = "Dungeoneingänge anzeigen"
LOCALES.deDE["MARK_LEVELS"] = "Stufe %s"
LOCALES.deDE["MARK_TURNIN"] = "Questabgabe"
LOCALES.deDE["MARK_DONE"] = "fertig"
LOCALES.deDE["MARK_NEAREST"] = "Nächster Flugpunkt: %s"
LOCALES.deDE["MARK_CLICK"] = "Klick: in der Liste auswählen"
LOCALES.frFR["OPT_WORLDART"] = "Carte du continent avec frontières (désactivé : carte du maître de vol)"
LOCALES.frFR["OPT_ZONENAMES"] = "Noms et surbrillance des zones"
LOCALES.frFR["OPT_QUESTMARKS"] = "Afficher les rendus de quête (journal)"
LOCALES.frFR["OPT_DUNGEONMARKS"] = "Afficher les entrées de donjon"
LOCALES.frFR["MARK_LEVELS"] = "Niveau %s"
LOCALES.frFR["MARK_TURNIN"] = "Rendu de quête"
LOCALES.frFR["MARK_DONE"] = "terminée"
LOCALES.frFR["MARK_NEAREST"] = "Point de vol le plus proche : %s"
LOCALES.frFR["MARK_CLICK"] = "Clic : le sélectionner dans la liste"
LOCALES.esES["OPT_WORLDART"] = "Mapa del continente con fronteras (desactivado: mapa del maestro de vuelo)"
LOCALES.esES["OPT_ZONENAMES"] = "Nombres y resaltado de zonas"
LOCALES.esES["OPT_QUESTMARKS"] = "Mostrar entregas de misiones (registro)"
LOCALES.esES["OPT_DUNGEONMARKS"] = "Mostrar entradas de mazmorras"
LOCALES.esES["MARK_LEVELS"] = "Nivel %s"
LOCALES.esES["MARK_TURNIN"] = "Entrega de misión"
LOCALES.esES["MARK_DONE"] = "lista"
LOCALES.esES["MARK_NEAREST"] = "Punto de vuelo más cercano: %s"
LOCALES.esES["MARK_CLICK"] = "Clic: seleccionarlo en la lista"
LOCALES.ruRU["OPT_WORLDART"] = "Карта континента с границами зон (выкл.: карта распорядителя)"
LOCALES.ruRU["OPT_ZONENAMES"] = "Названия и подсветка зон"
LOCALES.ruRU["OPT_QUESTMARKS"] = "Показывать сдачу заданий (журнал)"
LOCALES.ruRU["OPT_DUNGEONMARKS"] = "Показывать входы в подземелья"
LOCALES.ruRU["MARK_LEVELS"] = "Уровень %s"
LOCALES.ruRU["MARK_TURNIN"] = "Сдача задания"
LOCALES.ruRU["MARK_DONE"] = "готово"
LOCALES.ruRU["MARK_NEAREST"] = "Ближайшая точка полёта: %s"
LOCALES.ruRU["MARK_CLICK"] = "Щелчок: выбрать в списке"
LOCALES.zhCN["OPT_WORLDART"] = "显示带区域边界的大陆地图（关闭：飞行管理员地图）"
LOCALES.zhCN["OPT_ZONENAMES"] = "区域名称与区域高亮"
LOCALES.zhCN["OPT_QUESTMARKS"] = "显示任务交付位置（任务日志）"
LOCALES.zhCN["OPT_DUNGEONMARKS"] = "显示地下城入口"
LOCALES.zhCN["MARK_LEVELS"] = "等级 %s"
LOCALES.zhCN["MARK_TURNIN"] = "任务交付"
LOCALES.zhCN["MARK_DONE"] = "已完成"
LOCALES.zhCN["MARK_NEAREST"] = "最近的飞行点：%s"
LOCALES.zhCN["MARK_CLICK"] = "点击：在列表中选中"
LOCALES.zhTW["OPT_WORLDART"] = "顯示帶區域邊界的大陸地圖（關閉：飛行管理員地圖）"
LOCALES.zhTW["OPT_ZONENAMES"] = "區域名稱與區域高亮"
LOCALES.zhTW["OPT_QUESTMARKS"] = "顯示任務回報位置（任務日誌）"
LOCALES.zhTW["OPT_DUNGEONMARKS"] = "顯示地城入口"
LOCALES.zhTW["MARK_LEVELS"] = "等級 %s"
LOCALES.zhTW["MARK_TURNIN"] = "任務回報"
LOCALES.zhTW["MARK_DONE"] = "已完成"
LOCALES.zhTW["MARK_NEAREST"] = "最近的飛行點：%s"
LOCALES.zhTW["MARK_CLICK"] = "點擊：在清單中選取"
LOCALES.enUS["SEA_BUTTON"] = "Map: %s"
LOCALES.enUS["SEA_AUTO"] = "Auto (%s)"
LOCALES.enUS["SEA_SPRING"] = "Spring"
LOCALES.enUS["SEA_SUMMER"] = "Summer"
LOCALES.enUS["SEA_AUTUMN"] = "Autumn"
LOCALES.enUS["SEA_WINTER"] = "Winter"
LOCALES.enUS["SEA_PLAIN"] = "Game map"
LOCALES.enUS["SEA_PARCHMENT"] = "Parchment"
LOCALES.enUS["SEA_TIP"] = "Click: change the map look (Auto changes with the month)"
LOCALES.koKR["SEA_BUTTON"] = "지도: %s"
LOCALES.koKR["SEA_AUTO"] = "자동 (%s)"
LOCALES.koKR["SEA_SPRING"] = "봄"
LOCALES.koKR["SEA_SUMMER"] = "여름"
LOCALES.koKR["SEA_AUTUMN"] = "가을"
LOCALES.koKR["SEA_WINTER"] = "겨울"
LOCALES.koKR["SEA_PLAIN"] = "기본 지도"
LOCALES.koKR["SEA_PARCHMENT"] = "양피지"
LOCALES.koKR["SEA_TIP"] = "클릭: 지도 모양 바꾸기 (자동은 달마다 계절이 바뀜)"
LOCALES.deDE["SEA_BUTTON"] = "Karte: %s"
LOCALES.deDE["SEA_AUTO"] = "Auto (%s)"
LOCALES.deDE["SEA_SPRING"] = "Frühling"
LOCALES.deDE["SEA_SUMMER"] = "Sommer"
LOCALES.deDE["SEA_AUTUMN"] = "Herbst"
LOCALES.deDE["SEA_WINTER"] = "Winter"
LOCALES.deDE["SEA_PLAIN"] = "Spielkarte"
LOCALES.deDE["SEA_PARCHMENT"] = "Pergament"
LOCALES.deDE["SEA_TIP"] = "Klick: Kartenstil wechseln (Auto wechselt mit dem Monat)"
LOCALES.frFR["SEA_BUTTON"] = "Carte : %s"
LOCALES.frFR["SEA_AUTO"] = "Auto (%s)"
LOCALES.frFR["SEA_SPRING"] = "Printemps"
LOCALES.frFR["SEA_SUMMER"] = "Été"
LOCALES.frFR["SEA_AUTUMN"] = "Automne"
LOCALES.frFR["SEA_WINTER"] = "Hiver"
LOCALES.frFR["SEA_PLAIN"] = "Carte du jeu"
LOCALES.frFR["SEA_PARCHMENT"] = "Parchemin"
LOCALES.frFR["SEA_TIP"] = "Clic : changer le style de carte (Auto suit le mois)"
LOCALES.esES["SEA_BUTTON"] = "Mapa: %s"
LOCALES.esES["SEA_AUTO"] = "Auto (%s)"
LOCALES.esES["SEA_SPRING"] = "Primavera"
LOCALES.esES["SEA_SUMMER"] = "Verano"
LOCALES.esES["SEA_AUTUMN"] = "Otoño"
LOCALES.esES["SEA_WINTER"] = "Invierno"
LOCALES.esES["SEA_PLAIN"] = "Mapa del juego"
LOCALES.esES["SEA_PARCHMENT"] = "Pergamino"
LOCALES.esES["SEA_TIP"] = "Clic: cambiar el estilo del mapa (Auto cambia con el mes)"
LOCALES.ruRU["SEA_BUTTON"] = "Карта: %s"
LOCALES.ruRU["SEA_AUTO"] = "Авто (%s)"
LOCALES.ruRU["SEA_SPRING"] = "Весна"
LOCALES.ruRU["SEA_SUMMER"] = "Лето"
LOCALES.ruRU["SEA_AUTUMN"] = "Осень"
LOCALES.ruRU["SEA_WINTER"] = "Зима"
LOCALES.ruRU["SEA_PLAIN"] = "Карта игры"
LOCALES.ruRU["SEA_PARCHMENT"] = "Пергамент"
LOCALES.ruRU["SEA_TIP"] = "Щелчок: сменить вид карты (Авто меняется по месяцам)"
LOCALES.zhCN["SEA_BUTTON"] = "地图：%s"
LOCALES.zhCN["SEA_AUTO"] = "自动（%s）"
LOCALES.zhCN["SEA_SPRING"] = "春"
LOCALES.zhCN["SEA_SUMMER"] = "夏"
LOCALES.zhCN["SEA_AUTUMN"] = "秋"
LOCALES.zhCN["SEA_WINTER"] = "冬"
LOCALES.zhCN["SEA_PLAIN"] = "游戏地图"
LOCALES.zhCN["SEA_PARCHMENT"] = "羊皮纸"
LOCALES.zhCN["SEA_TIP"] = "点击：切换地图样式（自动按月份变化）"
LOCALES.zhTW["SEA_BUTTON"] = "地圖：%s"
LOCALES.zhTW["SEA_AUTO"] = "自動（%s）"
LOCALES.zhTW["SEA_SPRING"] = "春"
LOCALES.zhTW["SEA_SUMMER"] = "夏"
LOCALES.zhTW["SEA_AUTUMN"] = "秋"
LOCALES.zhTW["SEA_WINTER"] = "冬"
LOCALES.zhTW["SEA_PLAIN"] = "遊戲地圖"
LOCALES.zhTW["SEA_PARCHMENT"] = "羊皮紙"
LOCALES.zhTW["SEA_TIP"] = "點擊：切換地圖樣式（自動依月份變化）"
FLIGHT_TIPS_KO.worldArt = "비행 지도를 세계지도 그림으로 보여 주고 구역 경계를 표시합니다. 끄면 비행 조련사의 원래 지도를 씁니다."
FLIGHT_TIPS_KO.zoneNames = "지도에 구역 이름을 적고, 마우스를 올린 구역을 밝게 표시합니다."
FLIGHT_TIPS_KO.questMarks = "퀘스트 목록의 퀘스트를 보고할 위치를 표시합니다. 완료한 퀘스트는 노란 물음표로 크게 보입니다."
FLIGHT_TIPS_KO.dungeonMarks = "던전 입구와 권장 레벨을 표시합니다."
FLIGHT_TIPS_EN.worldArt = "Shows the flight map on the world map art with zone borders. Off: the flight master's own map."
FLIGHT_TIPS_EN.zoneNames = "Writes zone names on the map and lights up the zone under the cursor."
FLIGHT_TIPS_EN.questMarks = "Shows where quests in your quest log are turned in. Completed quests get a large yellow question mark."
FLIGHT_TIPS_EN.dungeonMarks = "Shows dungeon entrances with their level ranges."
FLIGHT_TIPS_OTHER.deDE.worldArt = "Zeigt die Flugkarte auf der Weltkarte mit Zonengrenzen. Aus: die Karte des Flugmeisters."
FLIGHT_TIPS_OTHER.deDE.zoneNames = "Schreibt Zonennamen auf die Karte und hebt die Zone unter dem Mauszeiger hervor."
FLIGHT_TIPS_OTHER.deDE.questMarks = "Zeigt, wo Quests aus dem Questlog abgegeben werden. Fertige Quests haben ein großes gelbes Fragezeichen."
FLIGHT_TIPS_OTHER.deDE.dungeonMarks = "Zeigt Dungeoneingänge mit Stufenbereich."
FLIGHT_TIPS_OTHER.frFR.worldArt = "Affiche la carte de vol sur la carte du monde avec les frontières. Désactivé : la carte du maître de vol."
FLIGHT_TIPS_OTHER.frFR.zoneNames = "Écrit les noms des zones et éclaire la zone sous le curseur."
FLIGHT_TIPS_OTHER.frFR.questMarks = "Montre où rendre les quêtes du journal. Les quêtes terminées ont un grand point d'interrogation jaune."
FLIGHT_TIPS_OTHER.frFR.dungeonMarks = "Affiche les entrées de donjon et leurs niveaux."
FLIGHT_TIPS_OTHER.esES.worldArt = "Muestra el mapa de vuelo sobre el mapa del mundo con fronteras. Desactivado: el mapa del maestro de vuelo."
FLIGHT_TIPS_OTHER.esES.zoneNames = "Escribe los nombres de zona y resalta la zona bajo el cursor."
FLIGHT_TIPS_OTHER.esES.questMarks = "Muestra dónde se entregan las misiones del registro. Las completadas llevan un gran signo de interrogación amarillo."
FLIGHT_TIPS_OTHER.esES.dungeonMarks = "Muestra las entradas de mazmorras con su rango de nivel."
FLIGHT_TIPS_OTHER.ruRU.worldArt = "Показывает карту полётов на карте мира с границами зон. Выкл.: карта распорядителя полётов."
FLIGHT_TIPS_OTHER.ruRU.zoneNames = "Пишет названия зон и подсвечивает зону под курсором."
FLIGHT_TIPS_OTHER.ruRU.questMarks = "Показывает, где сдавать задания из журнала. Готовые задания отмечены большим жёлтым вопросом."
FLIGHT_TIPS_OTHER.ruRU.dungeonMarks = "Показывает входы в подземелья и их уровни."
FLIGHT_TIPS_OTHER.zhCN.worldArt = "在世界地图图像上显示飞行地图和区域边界。关闭时使用飞行管理员的原始地图。"
FLIGHT_TIPS_OTHER.zhCN.zoneNames = "在地图上显示区域名称，并高亮鼠标所在区域。"
FLIGHT_TIPS_OTHER.zhCN.questMarks = "显示任务日志中任务的交付位置。已完成的任务显示为大的黄色问号。"
FLIGHT_TIPS_OTHER.zhCN.dungeonMarks = "显示地下城入口及等级范围。"
FLIGHT_TIPS_OTHER.zhTW.worldArt = "在世界地圖圖像上顯示飛行地圖和區域邊界。關閉時使用飛行管理員的原始地圖。"
FLIGHT_TIPS_OTHER.zhTW.zoneNames = "在地圖上顯示區域名稱，並高亮滑鼠所在區域。"
FLIGHT_TIPS_OTHER.zhTW.questMarks = "顯示任務日誌中任務的回報位置。已完成的任務顯示為大的黃色問號。"
FLIGHT_TIPS_OTHER.zhTW.dungeonMarks = "顯示地城入口及等級範圍。"
