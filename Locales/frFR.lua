-- French. Keys are the English texts (Locales/enUS.lua);
-- anything not translated here falls back to English.
-- Translations are AI-made: native speakers, please review (CurseForge's translation tool, or a pull request).
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:NewLocale(ADDON, "frFR")
if not L then
  return
end

L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "%d ventes et achats à l'HV ces 90 derniers jours. AME les enregistre depuis le courrier des enchères : ouvrez votre boîte aux lettres pour récupérer les nouveaux."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "%d enchères actives sur vos personnages, à la dernière ouverture de l'hôtel des ventes par chacun. Les ventes apparaissent tout de suite dans le journal et sont réglées à l'arrivée du courrier des enchères."
L["%d auctions"] = "%d enchères"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "%d clients ces 90 derniers jours, par or dépensé chez vous (d'après le courrier des enchères)."
L["%d days"] = "%d jours"
L["%d days ago"] = "il y a %d jours"
L["%d h ago"] = "il y a %d h"
L["%d h listings"] = "annonces de %d h"
L["%d items  -  showing %d-%d  -  index from %s"] = "%d objets  -  affichés %d-%d  -  index de %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d objets issus de %s annonces, stockés %s ms après la demande de scan"
L["%d items not searchable yet (names loading)"] = "%d objets pas encore cherchables (noms en chargement)"
L["%d items summarized"] = "%d objets résumés"
L["%d items summarized in %s ms wall"] = "%d objets résumés en %s ms (temps réel)"
L["%d min ago"] = "il y a %d min"
L["%d of %d known prices differ more than %dx from ours"] =
  "%d prix connus sur %d diffèrent de plus de %dx des nôtres"
L["%d passed, %d warnings, %d failed"] = "%d réussis, %d avertissements, %d échoués"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d positions sur %d personnage. Les sacs se mettent à jour en jeu ; ouvrez votre banque et l'hôtel des ventes pour inclure les objets en banque et les enchères actives."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d positions sur %d personnages. Les sacs se mettent à jour en jeu ; ouvrez votre banque et l'hôtel des ventes pour inclure les objets en banque et les enchères actives."
L["%d routes  -  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"] =
  "%d routes  -  achat à l'%s, vente à l'%s : commission %d%%, dépôts pour des annonces de %d h"
L["%d scans in 7 days"] = "%d scans en 7 jours"
L["%d scans/7d, %s"] = "%d scans/7j, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "%d fournisseurs ces 90 derniers jours, par or que vous leur avez versé (d'après le courrier des enchères)."
L["%d watched items have no price history here yet"] = "%d objets suivis n'ont pas encore d'historique de prix ici"
L["%d-day average"] = "Moyenne sur %d jours"
L["%dd avg"] = "moy. %dj"
L["%dx off usual"] = "%dx l'habituel"
L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"] =
  "%s  -  créé par Tyken Evanion  -  JcJ Horde, WoW Forever"
L["%s  ·  %d days of history  ·  data %s %s%s%s"] = "%s  ·  %d jours d'historique  ·  données %s %s%s%s"
L["%s %s: min %s, market %s, qty %d (%d samples)"] = "%s %s : min %s, marché %s, qté %d (%d échantillons)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s dernier (%s) : min %s, marché %s, %d unités en %d enchères"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s souhaite partager des prix d'enchères avec vous. Ouvrez |cffffffff/ame|r > Synchro pour accepter."
L["(each point is one scan)"] = "(chaque point est un scan)"
L["+ %d more"] = "+ %d de plus"
L[", %d scans received"] = ", %d scans reçus"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it"] =
  "/ame - ouvrir la fenêtre  ·  /ame <lien d'objet> - graphique d'un objet  ·  Alt-clic sur un objet - son graphique"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - ouvrir la fenêtre.   /ame <lien d'objet> - graphique d'un objet.   /ame status - état des données et de la synchro.   /ame config - paramètres.   /ame selftest - vérifier que tout fonctionne."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <lien> - afficher l'historique  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/sem."
L["1 day"] = "1 jour"
L["30 days: sold / bought"] = "30 jours : vendu / acheté"
L["7-day change"] = "Variation 7 j"
L["7d"] = "7j"
L["7d average"] = "Moyenne 7 jours"
L["7d avg"] = "Moy. 7j"
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Un screener sur tous les objets ayant un historique. Choisissez une catégorie ou une liste de suivi à gauche, cherchez par nom, filtrez par qualité, fourchette de prix ou signal, et cliquez sur une colonne pour trier. Survolez un en-tête de colonne pour sa signification. Cliquez sur une ligne pour ouvrir son graphique ; cliquez sur l'étoile pour le suivre."
L["AH cut"] = "Commission HV"
L["AME alert: %s %s"] = "Alerte AME : %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "AME écoute les API de l'hôtel des ventes du jeu lui-même, donc chaque scan et chaque recherche que vous lancez est enregistré - depuis la fenêtre d'hôtel des ventes par défaut ou n'importe quel addon de scan (il fonctionne bien avec des addons comme Auctionator). Rien n'est scanné en plus. L'historique est conservé par marché (royaume ou règles Forever) et par hôtel des ventes, et les membres de guilde utilisant AME partagent automatiquement leurs scans complets."
L["AceComm not available: sync disabled"] = "AceComm indisponible : synchro désactivée"
L["Activity"] = "Activité"
L["Add"] = "Ajouter"
L["Alert when"] = "Alerter quand"
L["Alert:"] = "Alerte :"
L["All"] = "Tout"
L["All items"] = "Tous les objets"
L["All markets: %d, %.0f KB of compressed daily history"] =
  "Tous les marchés : %d, %.0f Ko d'historique quotidien compressé"
L["Alliance AH"] = "HV Alliance"
L["Alliance blue"] = "Bleu Alliance"
L["Always show full tooltip details (otherwise hold Shift)"] =
  "Toujours afficher tous les détails de l'infobulle (sinon maintenir Maj)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Un classement des opportunités de -100 à +100. Plus il est haut, plus l'objet est sous son prix habituel, stable et en tendance haussière. Autour de 0, le prix est normal ; négatif, il est plus cher que d'habitude. Triez dessus pour trouver vite les bonnes affaires."
L["Announce recorded full scans in chat"] = "Annoncer les scans complets enregistrés dans le chat"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "Annoncé %d fois, %d scans servis, %d reçus, %d rejetés"
L["Announces your recent full scans to the guild and fetches ones you're missing, paced in the background so it never disrupts chat or raid addons. Received scans that disagree wildly with your own prices are rejected."] =
  "Annonce vos scans complets récents à la guilde et récupère ceux qui vous manquent, au rythme de l'arrière-plan pour ne jamais perturber le chat ou les addons de raid. Les scans reçus qui contredisent fortement vos propres prix sont rejetés."
L["Any age"] = "Tout âge"
L["Any quality"] = "Toute qualité"
L["Approve"] = "Accepter"
L["Arbitrage"] = "Arbitrage"
L["Arbitrage tab"] = "Onglet Arbitrage"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "Demande de partage envoyée à %s. Il la verra dans son onglet Synchro."
L["Asking prices"] = "Prix demandés"
L["At market price"] = "Au prix du marché"
L["Auction house"] = "Hôtel des ventes"
L["Auction house cut"] = "Commission de l'HV"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator n'est pas installé : rien à importer (les scans sont enregistrés depuis le jeu de toute façon)"
L["Auctions"] = "Enchères"
L["Average"] = "Moyenne"
L["Average cost"] = "Coût moyen"
L["Avg cost"] = "Coût moy."
L["BUY"] = "ACHETER"
L["BUY signal at %s"] = "Signal ACHAT à %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  "ACHETER : le prix du jour est anormalement bas pour cet objet - au moins 1,5 écart-type sous sa propre moyenne sur 30 jours. VENDRE : anormalement haut selon la même mesure. GARDER : dans sa fourchette normale - gardez-le si vous l'avez, pas d'avantage à acheter. ATTENDRE : bon marché, mais les vendeurs bradent - attendez le creux. Nécessite 7+ jours d'historique (\"-\" d'ici là). La phase de marché compare l'évolution du prix sur la semaine avec l'offre : pénurie, demande stable, afflux de vendeurs, resserrement, équilibre, pression croissante, retrait des vendeurs, demande faible ou bradage. Le signal compare l'objet avec lui-même ; c'est un indice, pas un conseil financier."
L["Balanced"] = "Équilibre"
L["Block"] = "Bloquer"
L["Blocked"] = "Bloqué"
L["Buy at"] = "Achat à"
L["By your guild officers: %s"] = "Par vos officiers de guilde : %s"
L["Cancel"] = "Annuler"
L["Candles"] = "Bougies"
L["Change this if another addon (e.g. AHDB) also uses Alt-click on items."] =
  "Changez ceci si un autre addon (p. ex. AHDB) utilise aussi Alt-clic sur les objets."
L["Character"] = "Personnage"
L["Character name, e.g. First Last"] = "Nom du personnage, p. ex. Prénom Nom"
L["Chart style"] = "Style de graphique"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Vérifie chaque partie d'AME et propose un rechargement pour enregistrer les résultats."
L["Checks every part of the addon, records timings, then reloads the UI."] =
  "Vérifie chaque partie de l'addon, mesure les temps, puis recharge l'interface."
L["Class %d"] = "Classe %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Cliquez sur une ligne pour ouvrir son graphique de prix. Cliquez sur l'étoile pour l'ajouter à une liste de suivi. Les barres après le nom indiquent la fiabilité des chiffres : 3 vertes = beaucoup de scans récents, 2 orange = quelques-uns, 1 rouge = peu ou anciens."
L["Close"] = "Fermer"
L["Commands"] = "Commandes"
L["Common+"] = "Commun+"
L["Copy to my watchlists"] = "Copier dans mes listes de suivi"
L["Could not load history: %s"] = "Impossible de charger l'historique : %s"
L["Customers"] = "Clients"
L["Data"] = "Données"
L["Data quality"] = "Qualité des données"
L["Days to sell"] = "Jours pour vendre"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "Les jours où le prix d'un objet est autant de fois au-dessus (ou en dessous) des jours voisins sont exclus du screener, des signaux, des alertes et des graphiques - typiquement une seule annonce majorée de 1000% mise en vente dans un marché étroit. Dans un scan complet, AME ignore déjà les annonces chères : le prix du marché utilise la partie la moins chère de l'offre."
L["Decline"] = "Refuser"
L["Delete list..."] = "Supprimer la liste..."
L['Delete the watchlist "%s"?'] = 'Supprimer la liste de suivi "%s" ?'
L["Deposit"] = "Dépôt"
L["Deposits for"] = "Dépôts pour"
L["Depth"] = "Profondeur"
L["Disabled"] = "Désactivé"
L["Display"] = "Affichage"
L["Dumping"] = "Bradage"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Chaque bougie couvre un ou plusieurs jours. Elle ouvre à la clôture de la bougie précédente et clôture au prix du marché ; verte a clôturé plus haut, rouge plus bas. La fine mèche descend jusqu'à l'annonce la moins chère vue."
L["Epic+"] = "Épique+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Unités vendues par jour (estimation) là où vous vendriez. Comparez avec la quantité que vous comptez acheter : s'il s'en vend 5 par jour, 100 prendront des semaines."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Tout ce que possèdent vos personnages - sacs, banque et enchères actives - au prix du marché de l'hôtel des ventes de votre faction. Les objets en banque et les enchères sont comptés à la dernière ouverture de la banque / de l'hôtel des ventes."
L["Faction auction houses"] = "HV de faction"
L["Follow market"] = "Suivre le marché"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Pour les unités achetées à l'hôtel des ventes : leur valeur actuelle au prix du marché moins ce que vous avez payé. Cela devient un vrai profit quand vous vendez."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "D'après vos ventes aux enchères : ce que vous avez reçu après la commission de l'HV, moins ce que vous avez payé pour ces unités (achats les plus anciens d'abord). Les ventes d'objets ramassés ou fabriqués comptent en entier."
L["Goblin AH"] = "HV gobelin"
L["Goblin auction houses"] = "HV gobelins"
L["Goblin gold"] = "Or gobelin"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Or reçu des ventes aux enchères (après commission) et or dépensé en achats aux enchères ces 30 derniers jours."
L["Guide"] = "Guide"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Les officiers de guilde peuvent bloquer des joueurs pour tous : ajoutez une ligne "%s" aux informations de guilde.'
L["Guild watchlists"] = "Listes de suivi de la guilde"
L["Guild: %s"] = "Guilde : %s"
L["HOLD"] = "GARDER"
L["Held"] = "Détenu"
L["High"] = "Haut"
L["History not loaded yet."] = "Historique pas encore chargé."
L["Hold Shift for more AME data"] = "Maintenez Maj pour plus de données AME"
L["Holdings value"] = "Valeur des avoirs"
L["Horde AH"] = "HV Horde"
L["Horde red"] = "Rouge Horde"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "La vitesse d'écoulement de l'objet : unités disparues entre deux scans complets consécutifs de cet hôtel des ventes, par jour, sur la dernière semaine. Cela compte les annonces vendues, annulées et expirées, et les nouvelles annonces masquent certaines ventes : prenez-le comme un ordre de grandeur. Un objet bon marché qui ne se vend jamais est un piège ; un chiffre élevé signifie qu'une pile part vite. Nécessite quelques scans complets le même jour."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Combien de temps il faudrait pour vendre tout ce que vous détenez au rythme de vente actuel de l'objet (estimation)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Combien sont en vente dans les dernières données. Sur la page de l'objet, le % noté à côté est la tendance hebdomadaire de l'offre : une offre en baisse précède souvent une hausse des prix."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Combien d'unités vous pouvez acheter à l'HV d'achat avant que la route ne soit plus rentable, et le profit total : chaque annonce sous ce que rapporte une unité après commission. Il faut les annonces de l'objet, donc cherchez d'abord l'objet à l'HV d'achat (le bouton Rechercher le fait) - elles restent ensuite 6 heures. Vendre autant prend quand même du temps : vérifiez Ventes/j."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "De combien le prix du marché a bougé par rapport aux données d'il y a 7 jours. Vert : hausse, rouge : baisse."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "À quel point le prix saute d'un jour à l'autre (l'écart des variations quotidiennes en % calculé sur 30 jours). Un chiffre bas signifie un objet stable et prévisible ; un chiffre haut, des variations risquées - et de plus grosses opportunités."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "L'âge du plus ancien des deux prix. Des données fraîches des deux côtés rendent une route fiable - scannez les deux hôtels des ventes (les rerolls de ce compte comptent) avant d'acheter."
L["If Auctionator is installed: fills days that have no AME data from its recent price history."] =
  "Si Auctionator est installé : complète les jours sans données AME avec son historique de prix récent."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Si Auctionator est installé : importe ses prix quotidiens récents pour les jours où AME n'a pas de données (HV de faction)."
L["Ignore outrageous prices"] = "Ignorer les prix aberrants"
L["Import history from Auctionator"] = "Importer l'historique d'Auctionator"
L["Item"] = "Objet"
L["Item name, ID, or Shift-click an item"] = "Nom, ID ou Maj-clic sur un objet"
L["Item tab"] = "Onglet Objet"
L["Items"] = "Objets"
L["Items tracked"] = "Objets suivis"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Objets que vous pouvez acheter dans un hôtel des ventes et revendre dans un autre avec profit après la commission - p. ex. l'HV de votre faction et l'HV gobelin (inter-factions). Chaque hôtel des ventes a son propre historique, donc scannez les deux (les rerolls de ce compte comptent). Survolez les colonnes pour les détails."
L['Keep the AH open until AME says "recorded full scan".'] =
  "Gardez l'HV ouvert jusqu'à ce qu'AME affiche \"scan complet enregistré\"."
L["Last"] = "Dernier"
L["Last full scan"] = "Dernier scan complet"
L["Last full scan: %d items, %s"] = "Dernier scan complet : %d objets, %s"
L["Last received: %d items from %s, %s"] = "Dernière réception : %d objets de %s, %s"
L["Last rejected:"] = "Dernier rejet :"
L["Ledger"] = "Journal"
L["Left-click: window   Right-click: settings"] = "Clic gauche : fenêtre   Clic droit : paramètres"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 non chargée"
L["LibDeflate not loaded"] = "LibDeflate non chargée"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "En vente à l'HV d'achat / à l'HV de vente. L'idéal : beaucoup à acheter et peu de concurrence là où vous vendez ; un gros écart sur une seule annonce à l'HV d'achat peut disparaître vite."
L["Listed on the AH now"] = "En vente à l'HV"
L["Listed on the auction house now"] = "En vente à l'hôtel des ventes"
L["Loading history..."] = "Chargement de l'historique..."
L["Loading market data..."] = "Chargement des données de marché..."
L["Loading recent scans..."] = "Chargement des scans récents..."
L["Low (cheapest)"] = "Bas (le moins cher)"
L["Lowest"] = "Plus bas"
L["Margin"] = "Marge"
L["Market"] = "Marché"
L["Market price"] = "Prix du marché"
L["Market tab"] = "Onglet Marché"
L["Market: %s"] = "Marché : %s"
L["Modified click on items in bags, chat links and the auction house. Choose Alt+Shift if another addon (e.g. AHDB) already uses Alt-click."] =
  "Clic modifié sur les objets dans les sacs, les liens de chat et l'hôtel des ventes. Choisissez Alt+Maj si un autre addon (p. ex. AHDB) utilise déjà Alt-clic."
L["Mostly"] = "Surtout"
L["Name for the new watchlist:"] = "Nom de la nouvelle liste de suivi :"
L["New list"] = "Nouvelle liste"
L["New list..."] = "Nouvelle liste..."
L["No full scan recorded yet."] = "Aucun scan complet enregistré."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Pas encore d'historique pour cet objet. Cherchez-le à l'hôtel des ventes ou lancez un scan complet."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Pas encore de données de marché pour l'hôtel des ventes de votre faction - scannez-y pour évaluer vos avoirs."
L["No one yet."] = "Personne pour l'instant."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Pas encore d'historique de prix pour l'%s : scannez-y (tout personnage de ce compte compte) pour comparer."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Pas encore d'historique de prix pour l'%s : scannez-y (tout personnage de ce compte compte)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "Aucun scan de cet objet ces 2 derniers jours. L'historique quotidien est sur les autres périodes."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Personne pour l'instant. Ajoutez un ami ci-dessus - il lui faut aussi AME, et il doit accepter."
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Rien reçu pour l'instant - les scans arrivent quand quelqu'un avec qui vous partagez lance un scan complet."
L["Notifications"] = "Notifications"
L["Off"] = "Désactivé"
L["Open"] = "Ouverture"
L["Open an item's chart with"] = "Ouvrir le graphique d'un objet avec"
L["Open item charts with"] = "Ouvrir les graphiques avec"
L["Open the window with %s."] = "Ouvrez la fenêtre avec %s."
L["Pick two different auction houses."] = "Choisissez deux hôtels des ventes différents."
L["Play a sound when a watchlist alert fires"] = "Jouer un son quand une alerte de liste de suivi se déclenche"
L["Player"] = "Joueur"
L["Portfolio"] = "Portefeuille"
L["Portfolio tab"] = "Onglet Portefeuille"
L["Positions"] = "Positions"
L["Pressure building"] = "Pression croissante"
L["Price"] = "Prix"
L["Price each"] = "Prix unitaire"
L["Profit"] = "Profit"
L["Qty"] = "Qté"
L["Rare+"] = "Rare+"
L["Reading the numbers"] = "Lire les chiffres"
L["Realized profit"] = "Profit réalisé"
L["Realized profit, 7 days"] = "Profit réalisé, 7 jours"
L["Rebuild market index"] = "Reconstruire l'index du marché"
L["Recently heard from"] = "Entendus récemment"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Recalcule les résumés sur 30 jours utilisés par le screener, les infobulles et les alertes."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Enregistre les prix de l'hôtel des ventes à chaque scan et recherche que vous lancez (API natives ; fonctionne avec n'importe quel addon de scan), par royaume et par hôtel des ventes."
L["Reload UI"] = "Recharger l'interface"
L["Requests"] = "Demandes"
L["Reset"] = "Réinitialiser"
L["Run self-test"] = "Lancer l'autotest"
L["SELL"] = "VENDRE"
L["SELL signal at %s"] = "Signal VENTE à %s"
L["Score"] = "Score"
L["Search"] = "Rechercher"
L["Search items..."] = "Rechercher des objets..."
L["Seen in 3 days"] = "Vu sur 3 jours"
L["Seen in 7 days"] = "Vu sur 7 jours"
L["Seen today/yesterday"] = "Vu aujourd'hui/hier"
L["Sell at"] = "Vente à"
L["Sellers piling in"] = "Afflux de vendeurs"
L["Sellers withdrawing"] = "Retrait des vendeurs"
L["Sells for"] = "Se vend"
L["Sells per day (estimate)"] = "Ventes par jour (estimation)"
L["Sells per day at the sell house"] = "Ventes par jour à l'HV de vente"
L["Sells/d"] = "Ventes/j"
L["Settings"] = "Paramètres"
L["Share full scans with guild members who use AME"] =
  "Partager les scans complets avec les membres de guilde qui utilisent AME"
L["Share full scans with my guild (members running AME)"] =
  "Partager les scans complets avec ma guilde (membres avec AME)"
L["Share with guild"] = "Partager avec la guilde"
L["Share with trusted players (below)"] = "Partager avec les joueurs de confiance (ci-dessous)"
L["Sharing"] = "Partage"
L["Sharing settings are on the Sync tab. These options are also in the game's AddOns settings."] =
  "Les paramètres de partage sont dans l'onglet Synchro. Ces options se trouvent aussi dans les paramètres AddOns du jeu."
L["Shift-click to search the auction house"] = "Maj-clic pour chercher à l'hôtel des ventes"
L["Shortage"] = "Pénurie"
L["Show AME prices in item tooltips"] = "Afficher les prix AME dans les infobulles d'objet"
L["Show market data in item tooltips"] = "Afficher les données de marché dans les infobulles d'objet"
L["Show minimap button"] = "Afficher le bouton de la minicarte"
L["Signal"] = "Signal"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Signaux et score comparent un objet à son propre historique, il leur faut donc une semaine de données ou plus pour avoir un sens. Les objets bon marché ET stables (faible volatilité) ont le meilleur score. Une offre en baisse avec un prix stable est souvent un bon signe précoce. Rien de tout cela n'est un conseil - les marchés peuvent rester étranges un moment."
L["Sold / bought"] = "Vendu / acheté"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  "Cliquez sur l'étoile d'un objet pour le mettre dans une liste de suivi ; créez d'autres listes avec \"+ Nouvelle liste\" dans la barre latérale (clic droit sur une liste pour la partager avec votre guilde ou la supprimer ; les listes partagées des membres de guilde apparaissent sous les vôtres). Sur la page d'un objet, réglez une alerte : sous ou au-dessus d'un prix en or, ou quand un signal d'achat/vente apparaît. Les alertes sont vérifiées après chaque scan et annoncées dans le chat avec un son."
L["Steady demand"] = "Demande stable"
L["Suppliers"] = "Fournisseurs"
L["Supply"] = "Offre"
L["Swap"] = "Inverser"
L["Sync"] = "Synchro"
L["Sync is unavailable: the AceComm library didn't load."] =
  "Synchro indisponible : la bibliothèque AceComm n'a pas été chargée."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "Le prix du marché quotidien moyen sur la période choisie (Paramètres > Période de la moyenne, 7 jours par défaut). Comparez-le au prix du marché du jour pour voir si l'objet est bon marché ou cher en ce moment."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "L'annonce la moins chère à l'hôtel des ventes où vous achetez - ce que vous coûtent les premières unités."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "Le prix du marché à l'hôtel des ventes où vous vendez : ce à quoi l'objet se vend habituellement là-bas."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Alt-click any item in the game (bags, chat, the AH) to open it here."] =
  "Le graphique de prix : prix du marché, annonce la plus basse, moyenne sur 7 jours et offre. Passez aux bougies pour une vue de trading. La molette zoome, glisser déplace, double-clic réinitialise. Alt-clic sur n'importe quel objet en jeu (sacs, chat, HV) pour l'ouvrir ici."
L["The selling auction house's cut of the sale: 5% at faction auction houses and 15% at the goblin ones (WoW Forever's rates; adjustable in Settings). The deposit isn't subtracted - you get it back when the item sells."] =
  "La commission de l'hôtel des ventes vendeur : 5% aux HV de faction et 15% aux HV gobelins (taux de WoW Forever ; réglables dans les Paramètres). Le dépôt n'est pas déduit - il vous est rendu quand l'objet se vend."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Ce marché : %d jours d'historique, %d scans récents conservés en entier"
L["Tightening"] = "Resserrement"
L["Time left"] = "Temps restant"
L["Top buy signals"] = "Meilleurs signaux d'achat"
L["Total"] = "Total"
L["Trusted"] = "De confiance"
L["Trusted (%d)"] = "De confiance (%d)"
L["Trusted players"] = "Joueurs de confiance"
L["Type %d"] = "Type %d"
L["Unblock"] = "Débloquer"
L["Uncommon+"] = "Inhabituel+"
L["Unrealized"] = "Latent"
L["Unrealized profit"] = "Profit latent"
L["Value"] = "Valeur"
L["Volatility"] = "Volatilité"
L["WAIT"] = "ATTENDRE"
L["Watch"] = "Suivre"
L["Watchlists and alerts"] = "Listes de suivi et alertes"
L["Weak demand"] = "Demande faible"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "Ce que possèdent tous vos personnages, évalué au marché de votre faction, avec le coût et le profit latent de ce que vous avez acheté à l'HV, le signal Acheter/Garder/Vendre et le temps qu'il faudrait pour vendre. Le journal liste vos ventes et achats à l'HV - enregistrés depuis le courrier des enchères quand vous ouvrez votre boîte aux lettres."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Ce que coûte d'avance la mise en vente d'une unité à l'HV de vente : une part du prix marchand de l'objet (HV de faction : 5/20/60% fixés pour 2/8/24 heures, HV gobelin cinq fois plus), au moins 1 argent. Il vous est rendu si l'objet se vend et perdu sinon - un dépôt élevé sur un objet qui se vend lentement est donc un vrai risque."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "Ce à quoi l'objet se vend habituellement en ce moment. Avec les données complètes des annonces, c'est la moyenne des 15-30% offrant les prix les plus bas parmi l'offre de l'hôtel des ventes, ce qui ignore quelques annonces bradées ou absurdes. Avec un résumé de navigation (ce que font par défaut beaucoup de scanners), seule l'annonce la moins chère est connue : c'est alors le prix le plus bas."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Ce que vous avez payé par unité pour les unités achetées à l'hôtel des ventes (les achats les plus anciens sont vendus en premier). Les objets ramassés ou fabriqués n'ont pas de coût."
L["When"] = "Quand"
L["Where the data comes from"] = "D'où viennent les données"
L["Window colours"] = "Couleurs de la fenêtre"
L["You haven't blocked anyone."] = "Vous n'avez bloqué personne."
L["You'd receive (after the cut)"] = "Vous recevriez (après commission)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Vos enchères actives sur tous vos personnages, à la dernière ouverture de l'hôtel des ventes par chacun."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "Vos rerolls sur ce compte Battle.net partagent déjà tout : l'historique d'AME est enregistré pour tout le compte. Accordez votre confiance à des joueurs pour échanger des scans avec des amis, ou avec vos propres personnages sur d'autres comptes. Seuls votre marché et votre hôtel des ventes sont partagés, et les scans qui contredisent fortement vos prix sont rejetés."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "Sur ce client, votre courrier des enchères ne nomme pas l'autre joueur (l'hôtel des ventes le garde anonyme), il n'y a donc personne à lister."
L["a list needs a name"] = "une liste doit avoir un nom"
L["a list with that name already exists"] = "une liste porte déjà ce nom"
L["above g"] = "sup. po"
L["announced %d, served %d, received %d, rejected %d"] = "annoncé %d, servi %d, reçu %d, rejeté %d"
L["auctionator history import"] = "import de l'historique Auctionator"
L["average period"] = "période de la moyenne"
L["awaiting mail"] = "courrier en attente"
L["backfill"] = "backfill"
L["below g"] = "inf. po"
L["blocked"] = "bloqué"
L["blocked %s"] = "%s bloqué"
L["bought"] = "acheté"
L["chart library + window"] = "bibliothèque de graphiques + fenêtre"
L["codec+compress 6.4k items"] = "codec+compression 6,4k objets"
L["could not load %s: %s"] = "impossible de charger %s : %s"
L["could not load history addon"] = "impossible de charger l'addon d'historique"
L["couldn't start an auction house search for %s"] = "impossible de lancer une recherche à l'hôtel des ventes pour %s"
L["data"] = "données"
L["done %s"] = "terminé %s"
L["down  (wick = cheapest)"] = "baisse  (mèche = moins cher)"
L["dropped to %s (alert at %s)"] = "tombé à %s (alerte à %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "encodage %.0f ms, compression %.0f ms, décompression+décodage %.0f ms, %d Ko -> %d Ko"
L["ended?"] = "terminée ?"
L["enter a character name"] = "saisissez un nom de personnage"
L["guild sync"] = "synchro de guilde"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "synchro de guilde : %s, annoncé %d, servi %d, reçu %d, rejeté %d"
L["history addon"] = "addon d'historique"
L["history import from Auctionator failed: %s"] = "échec de l'import de l'historique Auctionator : %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "l'import de l'historique Auctionator ne se fait qu'à l'hôtel des ventes de votre faction (ses données mélangent tous les HV)."
L["history import from Auctionator skipped: %s"] = "import de l'historique Auctionator ignoré : %s"
L["history lookup (cold)"] = "lecture de l'historique (à froid)"
L["history: %d raw scans, %d days, %.0f KB"] = "historique : %d scans bruts, %d jours, %.0f Ko"
L["imported %d days of price history from Auctionator into %s"] =
  "%d jours d'historique de prix importés d'Auctionator dans %s"
L["item %d: %d points in %.1f ms"] = "objet %d : %d points en %.1f ms"
L["item from latest scan has no daily points"] = "l'objet du dernier scan n'a pas de points quotidiens"
L["item not loaded yet - try again in a moment"] = "objet pas encore chargé - réessayez dans un instant"
L["just now"] = "à l'instant"
L["last full scan"] = "dernier scan complet"
L["last full scan: %d items, %s ago"] = "dernier scan complet : %d objets, il y a %s"
L["last seen %s"] = "vu pour la dernière fois %s"
L["libraries"] = "bibliothèques"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] =
  "chargé en %s ms, %d fragment(s), %.0f Ko d'historique quotidien"
L["loading history..."] = "chargement de l'historique..."
L["loading item names %d/%d"] = "chargement des noms d'objets %d/%d"
L["low"] = "bas"
L["lowest"] = "plus bas"
L["margin %"] = "marge %"
L["market"] = "marché"
L["market index"] = "index du marché"
L["market index failed:"] = "échec de l'index du marché :"
L["max g"] = "max po"
L["min g"] = "min po"
L["never"] = "jamais"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "aucun scan complet enregistré : ouvrez l'HV et lancez un scan complet (celui de votre addon de scan ou du jeu)"
L["no history for %s in %s"] = "pas d'historique pour %s dans %s"
L["no scans in this shard yet"] = "aucun scan dans ce fragment pour l'instant"
L["none"] = "aucun"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "aucun pour l'instant : ouvrez l'HV et lancez un scan complet, puis relancez /ame selftest"
L["not in a guild"] = "pas dans une guilde"
L["not loaded"] = "non chargé"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "rien d'importé ici (seulement avec les données d'Auctionator, à l'hôtel des ventes de votre faction)"
L["off"] = "désactivé"
L["on"] = "activé"
L["on buy/sell signal"] = "sur signal d'achat/vente"
L["on, but you're not in a guild"] = "activé, mais vous n'êtes pas dans une guilde"
L["open the auction house first"] = "ouvrez d'abord l'hôtel des ventes"
L["profit g"] = "profit po"
L["reading full scan (%d listings) in the background..."] = "lecture du scan complet (%d annonces) en arrière-plan..."
L["received a full scan from %s via sync (%d items, %s)"] = "scan complet reçu de %s par synchro (%d objets, %s)"
L["recorded full scan: %d items from %d listings (%s)"] =
  "scan complet enregistré : %d objets issus de %d annonces (%s)"
L["rose to %s (alert at %s)"] = "monté à %s (alerte à %s)"
L["round trip mismatch"] = "incohérence aller-retour"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "pipeline de scan : %d requêtes, %d événements (%d depuis la dernière requête), lu %s, abandonné %d ; ingestion demandée=%s lecture=%s"
L["scan read failed:"] = "échec de lecture du scan :"
L["score"] = "score"
L["score %+d"] = "score %+d"
L["search"] = "rechercher"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "autotest terminé :\n%s\n\nRecharger l'interface maintenant pour enregistrer les résultats ?"
L["selftest starting (this may pause the game for a moment)"] =
  "démarrage de l'autotest (le jeu peut se figer un instant)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "autotest : %d réussis, %d avertissements, %d échoués. Rechargez pour enregistrer les résultats (/reload)."
L["shard"] = "fragment"
L["shared"] = "partagée"
L["sharing"] = "partage"
L["signal"] = "signal"
L["sold"] = "vendu"
L["storing %s scan failed:"] = "échec de l'enregistrement du scan %s :"
L["supply"] = "offre"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "l'HV a été fermé avant qu'AME ait fini de lire le scan complet ; il n'a pas été enregistré."
L["today"] = "aujourd'hui"
L["turned off in settings"] = "désactivé dans les paramètres"
L["unknown command, try /ame help"] = "commande inconnue, essayez /ame help"
L["up"] = "hausse"
L["usage: /ame item <item link or itemID>"] = "utilisation : /ame item <lien d'objet ou ID d'objet>"
L["volatility"] = "volatilité"
L["waiting for them to approve"] = "en attente de leur accord"
L["wants to share, %s"] = "souhaite partager, %s"
L["wheel: zoom, drag: pan, double-click: reset"] = "molette : zoom, glisser : déplacer, double-clic : réinitialiser"
L["whisper"] = "chuchotement"
L["window created, market tab rendered"] = "fenêtre créée, onglet Marché affiché"
L["yesterday"] = "hier"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "vous êtes à l'HV d'achat : Rechercher (ou Maj-clic sur une ligne) pour acheter"
L["%d ahead"] = "%d devant"
L["<1h"] = "<1 h"
L["Normal %s"] = "Normal %s"
L["Patient %s"] = "Patient %s"
L["Post at"] = "Mettre en vente à"
L["Posting price"] = "Prix de mise en vente"
L["Posting price: not enough data on this item yet."] =
  "Prix de mise en vente : pas encore assez de données sur cet objet."
L["Quick %s"] = "Rapide %s"
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "À quel prix mettre en vente pour que l'objet se vende pendant la durée de l'annonce - au lieu de passer de 1 cuivre sous l'annonce la moins chère. Les acheteurs prennent d'abord les annonces les moins chères : AME compte donc les unités devant vous à chaque prix, la vitesse de vente de l'objet et la fréquence à laquelle de nouvelles annonces passent sous votre prix, puis met en balance la chance de vendre et le dépôt que vous perdez si l'objet ne se vend pas. Rapide vend presque sûrement en quelques heures, Normal est le meilleur prix compte tenu de la chance de vente, Patient est le prix le plus élevé qui vend encore environ une fois sur deux. AME apprend le profil de chaque objet à partir de vos scans (heures d'affluence, jours de la semaine, intensité de la concurrence entre vendeurs) et de vos propres annonces : si des objets expirent souvent à ses prix, il devient plus prudent pour cet objet. Avec peu de données, il s'appuie sur des objets similaires ; les barres montrent ce qu'il sait."
L["a week+"] = "une semaine+"
L["deposit %s"] = "dépôt %s"
L["unlikely to sell soon: consider holding"] = "peu de chances de vendre bientôt : envisagez de garder"
L["well below its usual price"] = "bien en dessous de son prix habituel"
L["~%d days"] = "~%d jours"
L["~%dh"] = "~%d h"
