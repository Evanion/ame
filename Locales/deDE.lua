-- German. Keys are the English texts (Locales/enUS.lua);
-- anything not translated here falls back to English.
-- Translations are AI-made: native speakers, please review (CurseForge's translation tool, or a pull request).
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:NewLocale(ADDON, "deDE")
if not L then
  return
end

L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "%d AH-Verkäufe und -Käufe in den letzten 90 Tagen. AME erfasst sie aus der Auktionspost: Öffne deinen Briefkasten, um neue zu erfassen."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "%d aktive Auktionen deiner Charaktere, Stand jeweils beim letzten Öffnen des Auktionshauses. Verkäufe erscheinen sofort im Journal und werden abgerechnet, sobald die Auktionspost eintrifft."
L["%d ahead"] = "%d davor"
L["%d auctions"] = "%d Auktionen"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "%d Kunden in den letzten 90 Tagen, nach Gold, das sie bei dir ausgegeben haben (aus der Auktionspost)."
L["%d days"] = "%d Tage"
L["%d days ago"] = "vor %d Tagen"
L["%d h ago"] = "vor %d Std."
L["%d h listings"] = "%d-Std.-Auktionen"
L["%d items  ·  showing %d-%d  ·  index from %s"] = "%d Gegenstände  ·  zeige %d-%d  ·  Index von %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d Gegenstände aus %s Angeboten, gespeichert %s ms nach der Scan-Anfrage"
L["%d items not searchable yet (names loading)"] = "%d Gegenstände noch nicht durchsuchbar (Namen werden geladen)"
L["%d items summarized"] = "%d Gegenstände zusammengefasst"
L["%d items summarized in %s ms wall"] = "%d Gegenstände in %s ms (Echtzeit) zusammengefasst"
L["%d min ago"] = "vor %d Min."
L["%d of %d known prices differ more than %dx from ours"] =
  "%d von %d bekannten Preisen weichen mehr als %dx von unseren ab"
L["%d passed, %d warnings, %d failed"] = "%d bestanden, %d Warnungen, %d fehlgeschlagen"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d Positionen auf %d Charakter. Taschen werden beim Spielen aktualisiert; öffne deine Bank und das Auktionshaus, um Bankgegenstände und aktive Auktionen einzubeziehen."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d Positionen auf %d Charakteren. Taschen werden beim Spielen aktualisiert; öffne deine Bank und das Auktionshaus, um Bankgegenstände und aktive Auktionen einzubeziehen."
L["%d routes  ·  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"] =
  "%d Routen  ·  Kauf im %s, Verkauf im %s: %d%% Gebühr, Anzahlung für %d-Std.-Auktionen"
L["%d scans in 7 days"] = "%d Scans in 7 Tagen"
L["%d scans/7d, %s"] = "%d Scans/7T, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "%d Lieferanten in den letzten 90 Tagen, nach Gold, das du bei ihnen ausgegeben hast (aus der Auktionspost)."
L["%d watched items have no price history here yet"] = "%d beobachtete Gegenstände haben hier noch keinen Preisverlauf"
L["%d-day average"] = "%d-Tage-Durchschnitt"
L["%dd avg"] = "Ø %dT"
L["%dx off usual"] = "%dx vom Üblichen"
L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"] =
  "%s  -  erstellt von Tyken Evanion  -  PvP Horde, WoW Forever"
L["%s  ·  %d days of history  ·  data %s %s%s%s"] = "%s  ·  %d Tage Verlauf  ·  Daten %s %s%s%s"
L["%s %s: min %s, market %s, qty %d (%d samples)"] = "%s %s: Min. %s, Markt %s, Menge %d (%d Stichproben)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s aktuell (%s): Min. %s, Markt %s, %d Stück in %d Auktionen"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s möchte Auktionspreise mit dir teilen. Öffne |cffffffff/ame|r > Sync, um zuzustimmen."
L["(each point is one scan)"] = "(jeder Punkt ist ein Scan)"
L["+ %d more"] = "+ %d weitere"
L[", %d scans received"] = ", %d Scans empfangen"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it"] =
  "/ame - Fenster öffnen  ·  /ame <Gegenstandslink> - Chart anzeigen  ·  Alt-Klick auf einen Gegenstand - Chart anzeigen"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - Fenster öffnen.   /ame <Gegenstandslink> - Chart eines Gegenstands.   /ame status - Daten- und Sync-Status.   /ame config - Einstellungen.   /ame selftest - prüfen, ob alles funktioniert."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <Link> - Verlauf ausgeben  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/Woche"
L["1 day"] = "1 Tag"
L["30 days: sold / bought"] = "30 Tage: verkauft / gekauft"
L["7-day change"] = "7-Tage-Änderung"
L["7d"] = "7T"
L["7d average"] = "7-Tage-Durchschnitt"
L["7d avg"] = "Ø 7T"
L["<1h"] = "<1 Std."
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Ein Screener über alle Gegenstände mit Verlauf. Wähle links eine Kategorie oder Beobachtungsliste, suche nach Namen, filtere nach Qualität, Preisspanne oder Signal und klicke zum Sortieren auf eine Spalte. Fahre über einen Spaltenkopf, um zu sehen, was er bedeutet. Klicke auf eine Zeile, um ihren Chart zu öffnen; klicke auf den Stern, um sie zu beobachten."
L["AH cut"] = "AH-Gebühr"
L["AME alert: %s %s"] = "AME-Alarm: %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "AME lauscht den Auktionshaus-Schnittstellen des Spiels selbst, daher wird jeder Scan und jede Suche erfasst - aus dem normalen Auktionshausfenster oder jedem Scan-Addon (funktioniert gut mit Addons wie Auctionator). Es wird nichts zusätzlich gescannt. Der Verlauf wird pro Markt (Realm oder Forever-Regelwerk) und Auktionshaus geführt, und Gildenmitglieder mit AME teilen ihre vollständigen Scans automatisch."
L["AceComm not available: sync disabled"] = "AceComm nicht verfügbar: Sync deaktiviert"
L["Activity"] = "Aktivität"
L["Add"] = "Hinzufügen"
L["Alert when"] = "Alarm, wenn"
L["Alert:"] = "Alarm:"
L["All"] = "Alle"
L["All items"] = "Alle Gegenstände"
L["All markets: %d, %.0f KB of compressed daily history"] = "Alle Märkte: %d, %.0f KB komprimierter Tagesverlauf"
L["Alliance AH"] = "Allianz-AH"
L["Alliance blue"] = "Allianzblau"
L["Always show full tooltip details (otherwise hold Shift)"] = "Immer alle Tooltip-Details zeigen (sonst Shift halten)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Eine Chancen-Wertung von -100 bis +100. Höher heißt: Der Gegenstand liegt weiter unter seinem üblichen Preis, ist stabil und im Aufwärtstrend. Um 0 heißt normaler Preis; negativ heißt teurer als üblich. Sortiere danach, um schnell Schnäppchen zu finden."
L["Announce recorded full scans in chat"] = "Erfasste vollständige Scans im Chat melden"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "%d-mal angekündigt, %d Scans geliefert, %d empfangen, %d abgelehnt"
L["Any age"] = "Beliebiges Alter"
L["Any quality"] = "Jede Qualität"
L["Approve"] = "Zustimmen"
L["Arbitrage"] = "Arbitrage"
L["Arbitrage tab"] = "Arbitrage-Reiter"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "%s wurde gebeten zu teilen. Die Anfrage erscheint im Sync-Reiter."
L["Asking prices"] = "Angebotspreise"
L["At market price"] = "Zum Marktpreis"
L["Auction house"] = "Auktionshaus"
L["Auction house cut"] = "Auktionshausgebühr"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator nicht installiert: nichts zu importieren (Scans werden ohnehin aus dem Spiel erfasst)"
L["Auctions"] = "Auktionen"
L["Average"] = "Durchschnitt"
L["Average cost"] = "Durchschnittskosten"
L["Avg cost"] = "Ø Kosten"
L["BUY"] = "KAUFEN"
L["BUY signal at %s"] = "KAUF-Signal bei %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  'KAUFEN: Der heutige Preis ist für diesen Gegenstand ungewöhnlich niedrig - mindestens 1,5 Standardabweichungen unter seinem eigenen 30-Tage-Durchschnitt. VERKAUFEN: ungewöhnlich hoch nach demselben Maß. HALTEN: im normalen Bereich - behalte ihn, wenn du ihn besitzt, kein Vorteil beim Kauf. WARTEN: günstig, aber Verkäufer werfen ab - warte auf den Boden. Benötigt 7+ Tage Verlauf ("-" bis dahin). Die Marktphase liest die Preisbewegung der Woche gegen das Angebot: Knappheit, stabile Nachfrage, Verkäufer strömen herein, Verknappung, ausgeglichen, Druck baut sich auf, Verkäufer ziehen sich zurück, schwache Nachfrage oder Abverkauf. Das Signal vergleicht den Gegenstand mit sich selbst und ist ein Hinweis, keine Finanzberatung.'
L["Balanced"] = "Ausgeglichen"
L["Block"] = "Blockieren"
L["Blocked"] = "Blockiert"
L["Buy at"] = "Kauf bei"
L["By your guild officers: %s"] = "Von deinen Gildenoffizieren: %s"
L["Cancel"] = "Abbrechen"
L["Candles"] = "Kerzen"
L["Change this if another addon (e.g. AHDB) also uses Alt-click on items."] =
  "Ändere dies, wenn ein anderes Addon (z. B. AHDB) ebenfalls Alt-Klick auf Gegenstände nutzt."
L["Character"] = "Charakter"
L["Character name, e.g. First Last"] = "Charaktername, z. B. Vorname Nachname"
L["Chart style"] = "Chart-Stil"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Prüft alle Teile von AME und bietet ein Neuladen an, damit die Ergebnisse gespeichert werden."
L["Class %d"] = "Klasse %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Klicke auf eine Zeile, um ihren Preischart zu öffnen. Klicke auf den Stern, um sie einer Beobachtungsliste hinzuzufügen. Die Balken nach dem Namen zeigen, wie verlässlich die Zahlen sind: 3 grün = viele aktuelle Scans, 2 gelb = einige, 1 rot = wenige oder alte."
L["Close"] = "Schließen"
L["Commands"] = "Befehle"
L["Common+"] = "Gewöhnlich+"
L["Copy to my watchlists"] = "In meine Beobachtungslisten kopieren"
L["Could not load history: %s"] = "Verlauf konnte nicht geladen werden: %s"
L["Customers"] = "Kunden"
L["Data"] = "Daten"
L["Data quality"] = "Datenqualität"
L["Days to sell"] = "Tage bis Verkauf"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "Tage, an denen der Preis eines Gegenstands so viele Male über (oder unter) den Nachbartagen liegt, werden aus Screener, Signalen, Alarmen und Charts herausgenommen - typischerweise ein einzelnes Angebot, 1000% mehr als üblich, in einem dünnen Markt. Innerhalb eines vollständigen Scans ignoriert AME teure Angebote bereits: Der Marktpreis nutzt den günstigsten Teil des Angebots."
L["Decline"] = "Ablehnen"
L["Delete list..."] = "Liste löschen..."
L['Delete the watchlist "%s"?'] = 'Beobachtungsliste "%s" löschen?'
L["Deposit"] = "Anzahlung"
L["Deposits for"] = "Anzahlung für"
L["Depth"] = "Tiefe"
L["Display"] = "Anzeige"
L["Dumping"] = "Abverkauf"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Jede Kerze umfasst einen oder mehrere Tage. Sie eröffnet beim Schluss der vorherigen Kerze und schließt beim Marktpreis; grün schloss höher, rot tiefer. Der dünne Docht reicht hinunter bis zum günstigsten gesehenen Angebot."
L["Epic+"] = "Episch+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Geschätzte verkaufte Stück pro Tag dort, wo du verkaufen würdest. Vergleiche das mit der Menge, die du kaufen willst: Wenn 5 pro Tag verkauft werden, dauern 100 Wochen."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Alles, was deine Charaktere besitzen - Taschen, Bank und aktive Auktionen - zum Marktpreis des Auktionshauses deiner Fraktion. Bankgegenstände und Auktionen zählen mit dem Stand beim letzten Öffnen von Bank / Auktionshaus."
L["Faction auction houses"] = "Fraktions-Auktionshäuser"
L["Follow market"] = "Markt folgen"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Für Stück, die du im Auktionshaus gekauft hast: was sie jetzt zum Marktpreis wert sind, minus was du bezahlt hast. Zum echten Gewinn wird es, wenn du verkaufst."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "Aus deinen Auktionsverkäufen: was du nach der AH-Gebühr erhalten hast, minus was du für diese Stück bezahlt hast (älteste Käufe zuerst). Verkäufe erbeuteter oder hergestellter Gegenstände zählen voll."
L["Goblin AH"] = "Goblin-AH"
L["Goblin auction houses"] = "Goblin-Auktionshäuser"
L["Goblin gold"] = "Goblin-Gold"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Gold aus Auktionsverkäufen (nach Gebühr) und für Auktionskäufe ausgegebenes Gold in den letzten 30 Tagen."
L["Guide"] = "Anleitung"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Gildenoffiziere können Spieler für alle blockieren: Füge die Zeile "%s" zur Gildeninfo hinzu.'
L["Guild watchlists"] = "Gilden-Beobachtungslisten"
L["Guild: %s"] = "Gilde: %s"
L["HOLD"] = "HALTEN"
L["Held"] = "Bestand"
L["High"] = "Hoch"
L["History not loaded yet."] = "Verlauf noch nicht geladen."
L["Hold Shift for more AME data"] = "Shift halten für mehr AME-Daten"
L["Holdings value"] = "Bestandswert"
L["Horde AH"] = "Horde-AH"
L["Horde red"] = "Hordenrot"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "Wie schnell sich der Gegenstand bewegt: Stück, die zwischen aufeinanderfolgenden vollständigen Scans dieses Auktionshauses verschwunden sind, pro Tag, über die letzte Woche. Gezählt werden verkaufte, abgebrochene und abgelaufene Angebote, und neue Angebote verdecken einige Verkäufe - also nur ein grober Richtwert. Ein billiger Gegenstand, der sich nie verkauft, ist eine Falle; eine hohe Zahl heißt, du wirst einen Stapel schnell los. Braucht ein paar vollständige Scans am selben Tag."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Wie lange es dauern würde, alles, was du besitzt, zur aktuellen Verkaufsrate des Gegenstands zu verkaufen (Schätzung)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Wie viele in den neuesten Daten angeboten werden. Auf der Gegenstandsseite ist die Angabe in % neben der Menge der wöchentliche Angebotstrend: Sinkendes Angebot kommt oft vor steigenden Preisen."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Wie viele Stück du im Kauf-AH kaufen kannst, bevor sich die Route nicht mehr lohnt, und der Gesamtgewinn: jedes Angebot unter dem, was eines nach Gebühr einbringt. Dafür braucht es die Angebote des Gegenstands, also suche ihn zuerst im Kauf-AH (der Suchen-Knopf erledigt das) - danach bleiben sie 6 Stunden erhalten. Diese Menge zu verkaufen braucht trotzdem Zeit: Prüfe Verk./T."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "Wie stark sich der Marktpreis gegenüber den Daten von vor 7 Tagen bewegt hat. Grün ist hoch, rot ist runter."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "Wie stark der Preis von Tag zu Tag springt (die Streuung der täglichen Änderungen in % contra Vortag über 30 Tage). Niedrige Werte heißen stabiler, berechenbarer Gegenstand; hohe Werte heißen riskante Schwankungen - und größere Chancen."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "Wie alt der ältere der beiden Preise ist. Frische Daten auf beiden Seiten machen eine Route vertrauenswürdig - scanne vor dem Kauf beide Auktionshäuser (Twinks auf diesem Account zählen)."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Wenn Auctionator installiert ist: importiert dessen jüngste Tagespreise für Tage, an denen AME keine Daten hat (Fraktions-AH)."
L["Ignore outrageous prices"] = "Absurde Preise ignorieren"
L["Import history from Auctionator"] = "Verlauf aus Auctionator importieren"
L["Item"] = "Gegenstand"
L["Item name, ID, or Shift-click an item"] = "Name, ID oder Shift-Klick auf einen Gegenstand"
L["Item tab"] = "Gegenstand-Reiter"
L["Items"] = "Gegenstände"
L["Items tracked"] = "Erfasste Gegenstände"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Gegenstände, die du in einem Auktionshaus kaufen und in einem anderen mit Gewinn nach AH-Gebühr verkaufen kannst - z. B. im AH deiner Fraktion und im Goblin-AH (fraktionsübergreifend). Jedes Auktionshaus hat seinen eigenen Verlauf, also scanne beide (Twinks auf diesem Account zählen). Fahre über die Spalten für Details."
L['Keep the AH open until AME says "recorded full scan".'] =
  'Lass das AH offen, bis AME "vollständiger Scan erfasst" meldet.'
L["Last"] = "Zuletzt"
L["Last full scan"] = "Letzter vollständiger Scan"
L["Last full scan: %d items, %s"] = "Letzter vollständiger Scan: %d Gegenstände, %s"
L["Last received: %d items from %s, %s"] = "Zuletzt empfangen: %d Gegenstände von %s, %s"
L["Last rejected:"] = "Zuletzt abgelehnt:"
L["Ledger"] = "Journal"
L["Left-click: window   Right-click: settings"] = "Linksklick: Fenster   Rechtsklick: Einstellungen"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 nicht geladen"
L["LibDeflate not loaded"] = "LibDeflate nicht geladen"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "Angeboten im Kauf-AH / im Verkaufs-AH. Ideal ist viel zum Kaufen und wenig Konkurrenz, wo du verkaufst; eine große Lücke bei einem einzelnen Angebot im Kauf-AH ist vielleicht schnell weg."
L["Listed on the AH now"] = "Jetzt im AH angeboten"
L["Listed on the auction house now"] = "Jetzt im Auktionshaus angeboten"
L["Loading history..."] = "Lade Verlauf..."
L["Loading market data..."] = "Lade Marktdaten..."
L["Loading recent scans..."] = "Lade letzte Scans..."
L["Low (cheapest)"] = "Tief (günstigstes)"
L["Lowest"] = "Niedrigster"
L["Margin"] = "Marge"
L["Market"] = "Markt"
L["Market price"] = "Marktpreis"
L["Market tab"] = "Markt-Reiter"
L["Market: %s"] = "Markt: %s"
L["Mostly"] = "Meistens"
L["Name for the new watchlist:"] = "Name der neuen Beobachtungsliste:"
L["New list"] = "Neue Liste"
L["New list..."] = "Neue Liste..."
L["No full scan recorded yet."] = "Noch kein vollständiger Scan erfasst."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Noch kein Verlauf für diesen Gegenstand. Suche ihn im Auktionshaus oder führe einen vollständigen Scan durch."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Noch keine Marktdaten für das Auktionshaus deiner Fraktion - scanne dort, um deinen Bestand zu bewerten."
L["No one yet."] = "Noch niemand."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Noch kein Preisverlauf für das %s: Scanne dort (jeder Charakter auf diesem Account zählt), um zu vergleichen."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Noch kein Preisverlauf für das %s: Scanne dort (jeder Charakter auf diesem Account zählt)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "Keine Scans dieses Gegenstands in den letzten 2 Tagen. Der Tagesverlauf ist in den anderen Zeiträumen."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Noch niemand. Füge oben einen Freund hinzu - er braucht ebenfalls AME und muss zustimmen."
L["Normal %s"] = "Normal %s"
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Noch nichts empfangen - Scans kommen an, wenn jemand, mit dem du teilst, einen vollständigen Scan durchführt."
L["Notifications"] = "Benachrichtigungen"
L["Off"] = "Aus"
L["Open"] = "Eröffnung"
L["Open item charts with"] = "Gegenstands-Charts öffnen mit"
L["Patient %s"] = "Geduldig %s"
L["Pick two different auction houses."] = "Wähle zwei verschiedene Auktionshäuser."
L["Play a sound when a watchlist alert fires"] = "Ton abspielen, wenn ein Beobachtungslisten-Alarm auslöst"
L["Player"] = "Spieler"
L["Portfolio"] = "Portfolio"
L["Portfolio tab"] = "Portfolio-Reiter"
L["Positions"] = "Positionen"
L["Post at"] = "Einstellen zu"
L["Posting price"] = "Einstellpreis"
L["Posting price: not enough data on this item yet."] = "Einstellpreis: noch nicht genug Daten zu diesem Gegenstand."
L["Pressure building"] = "Druck baut sich auf"
L["Price"] = "Preis"
L["Price each"] = "Stückpreis"
L["Profit"] = "Gewinn"
L["Qty"] = "Menge"
L["Quick %s"] = "Schnell %s"
L["Rare+"] = "Selten+"
L["Reading the numbers"] = "Die Zahlen lesen"
L["Realized profit"] = "Realisierter Gewinn"
L["Realized profit, 7 days"] = "Realisierter Gewinn, 7 Tage"
L["Rebuild market index"] = "Marktindex neu aufbauen"
L["Recently heard from"] = "Kürzlich gehört von"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Berechnet die 30-Tage-Zusammenfassungen hinter Screener, Tooltips und Alarmen neu."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Erfasst Auktionshauspreise aus jedem Scan und jeder Suche (native AH-Schnittstellen; funktioniert mit jedem Scan-Addon), pro Realm und Auktionshaus."
L["Reload UI"] = "UI neu laden"
L["Requests"] = "Anfragen"
L["Reset"] = "Zurücksetzen"
L["Run self-test"] = "Selbsttest starten"
L["SELL"] = "VERKAUFEN"
L["SELL signal at %s"] = "VERKAUF-Signal bei %s"
L["Score"] = "Score"
L["Search"] = "Suchen"
L["Search items..."] = "Gegenstände suchen..."
L["Seen in 3 days"] = "In 3 Tagen gesehen"
L["Seen in 7 days"] = "In 7 Tagen gesehen"
L["Seen today/yesterday"] = "Heute/gestern gesehen"
L["Sell at"] = "Verkauf bei"
L["Sellers piling in"] = "Verkäufer strömen herein"
L["Sellers withdrawing"] = "Verkäufer ziehen sich zurück"
L["Sells for"] = "Verkauft für"
L["Sells per day (estimate)"] = "Verkäufe pro Tag (Schätzung)"
L["Sells per day at the sell house"] = "Verkäufe pro Tag im Verkaufs-AH"
L["Sells/d"] = "Verk./T"
L["Settings"] = "Einstellungen"
L["Share full scans with my guild (members running AME)"] =
  "Vollständige Scans mit meiner Gilde teilen (Mitglieder mit AME)"
L["Share with guild"] = "Mit Gilde teilen"
L["Share with trusted players (below)"] = "Mit vertrauten Spielern teilen (unten)"
L["Sharing"] = "Teilen"
L["Sharing settings are on the Sync tab. These options are also in the game's AddOns settings."] =
  "Die Teilen-Einstellungen sind im Sync-Reiter. Diese Optionen gibt es auch in den AddOn-Einstellungen des Spiels."
L["Shift-click to search the auction house"] = "Shift-Klick, um im Auktionshaus zu suchen"
L["Shortage"] = "Knappheit"
L["Show AME prices in item tooltips"] = "AME-Preise in Gegenstands-Tooltips zeigen"
L["Show minimap button"] = "Minimap-Knopf zeigen"
L["Signal"] = "Signal"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Signale und Score vergleichen einen Gegenstand mit seinem eigenen Verlauf, brauchen also eine Woche oder mehr Daten, um etwas zu bedeuten. Gegenstände, die günstig UND stabil (niedrige Volatilität) sind, erzielen den höchsten Score. Sinkendes Angebot bei flachem Preis ist oft ein gutes frühes Zeichen. Nichts davon ist Beratung - Märkte können eine Weile verrückt bleiben."
L["Sold / bought"] = "Verkauft / gekauft"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  'Markiere Gegenstände mit dem Stern, um sie auf eine Beobachtungsliste zu setzen; weitere Listen erstellst du mit "+ Neue Liste" in der Seitenleiste (Rechtsklick auf eine Liste, um sie mit deiner Gilde zu teilen oder zu löschen; geteilte Listen von Gildenmitgliedern erscheinen unter deinen). Setze auf der Seite eines Gegenstands einen Alarm: unter oder über einem Preis in Gold oder wenn ein Kauf-/Verkaufssignal erscheint. Alarme werden nach jedem Scan geprüft und mit Ton im Chat gemeldet.'
L["Steady demand"] = "Stabile Nachfrage"
L["Suppliers"] = "Lieferanten"
L["Supply"] = "Angebot"
L["Swap"] = "Tauschen"
L["Sync"] = "Sync"
L["Sync is unavailable: the AceComm library didn't load."] =
  "Sync nicht verfügbar: Die AceComm-Bibliothek wurde nicht geladen."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "Der durchschnittliche tägliche Marktpreis über den gewählten Zeitraum (Einstellungen > Durchschnittszeitraum, standardmäßig 7 Tage). Vergleiche ihn mit dem heutigen Marktpreis, um zu sehen, ob der Gegenstand gerade günstig oder teuer ist."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "Das günstigste Angebot im Auktionshaus, in dem du kaufst - was dich die ersten Stück kosten."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "Der Marktpreis im Auktionshaus, in dem du verkaufst: wofür der Gegenstand dort typischerweise verkauft wird."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Alt-click any item in the game (bags, chat, the AH) to open it here."] =
  "Der Preischart: Marktpreis, niedrigstes Angebot, 7-Tage-Durchschnitt und Angebot. Wechsle zu Kerzen für eine Trading-Ansicht. Mausrad zoomt, Ziehen verschiebt, Doppelklick setzt zurück. Alt-Klick auf einen beliebigen Gegenstand im Spiel (Taschen, Chat, AH) öffnet ihn hier."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Dieser Markt: %d Tage Verlauf, %d letzte Scans vollständig gespeichert"
L["Tightening"] = "Verknappung"
L["Time left"] = "Restzeit"
L["Top buy signals"] = "Top-Kaufsignale"
L["Total"] = "Gesamt"
L["Trusted"] = "Vertraut"
L["Trusted (%d)"] = "Vertraut (%d)"
L["Trusted players"] = "Vertraute Spieler"
L["Type %d"] = "Typ %d"
L["Unblock"] = "Freigeben"
L["Uncommon+"] = "Ungewöhnlich+"
L["Unrealized"] = "Unrealisiert"
L["Unrealized profit"] = "Unrealisierter Gewinn"
L["Value"] = "Wert"
L["Volatility"] = "Volatilität"
L["WAIT"] = "WARTEN"
L["Watch"] = "Beobachten"
L["Watchlists and alerts"] = "Beobachtungslisten und Alarme"
L["Weak demand"] = "Schwache Nachfrage"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "Was alle deine Charaktere besitzen, bewertet zum Markt deiner Fraktion, mit Kosten und unrealisiertem Gewinn für das, was du im AH gekauft hast, dem Kaufen/Halten/Verkaufen-Signal und wie lange der Verkauf dauern würde. Das Journal listet deine AH-Verkäufe und -Käufe - erfasst aus der Auktionspost, wenn du deinen Briefkasten öffnest."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Was das Einstellen eines Stücks im Verkaufs-AH vorab kostet: ein Anteil am Händlerpreis des Gegenstands (Fraktions-AH 5/20/60% für 2/8/24 Stunden, Goblin-AH das Fünffache), mindestens 1 Silber. Du bekommst sie zurück, wenn er verkauft wird, und verlierst sie, wenn nicht - eine hohe Anzahlung bei einem Ladenhüter ist also ein echtes Risiko."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "Wofür der Gegenstand gerade typischerweise verkauft wird. Aus vollständigen Angebotsdaten ist es der Durchschnitt der günstigsten 15-30% ohne einige wenige billige oder absurde Ausreißer im Auktionshaus. Aus einer Übersicht (was viele Scanner standardmäßig liefern) ist nur das günstigste Angebot bekannt, dann ist es der niedrigste Preis."
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "Zu welchem Preis du einstellen solltest, damit es innerhalb der Auktionsdauer verkauft wird - statt die günstigste Auktion um 1 Kupfer zu unterbieten. Käufer nehmen die günstigsten Auktionen zuerst, daher zählt AME die Einheiten vor dir bei jedem Preis, wie schnell sich der Gegenstand verkauft und wie oft neue Auktionen dich unterbieten, und wägt die Verkaufschance gegen die Anzahlung ab, die du verlierst, wenn er nicht verkauft wird. Schnell verkauft fast sicher innerhalb weniger Stunden, Normal ist der beste Preis für die Chance, Geduldig ist der höchste Preis, der noch etwa in der Hälfte der Fälle verkauft. AME lernt das Muster jedes Gegenstands aus deinen Scans (Stoßzeiten, Wochentage, wie hart Verkäufer konkurrieren) und aus deinen eigenen Auktionen: Laufen Gegenstände zu seinen Preisen immer wieder ab, wird es bei diesem Gegenstand vorsichtiger. Bei wenig Daten orientiert es sich an ähnlichen Gegenständen; die Balken zeigen, wie viel es weiß."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Was du pro Stück für die im Auktionshaus gekauften Stück bezahlt hast (älteste Käufe werden zuerst verkauft). Erbeutete oder hergestellte Gegenstände haben keine Kosten."
L["When"] = "Wann"
L["Where the data comes from"] = "Woher die Daten kommen"
L["Window colours"] = "Fensterfarben"
L["You haven't blocked anyone."] = "Du hast niemanden blockiert."
L["You'd receive (after the cut)"] = "Du erhältst (nach Gebühr)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Deine aktiven Auktionen aller Charaktere, Stand jeweils beim letzten Öffnen des Auktionshauses."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "Deine Twinks auf diesem Battle.net-Account teilen bereits alles: Der Verlauf von AME wird accountweit gespeichert. Vertraue Spielern, um Scans mit Freunden oder deinen eigenen Charakteren auf anderen Accounts auszutauschen. Nur dein Markt und dein Auktionshaus werden geteilt, und Scans, die stark von deinen Preisen abweichen, werden abgelehnt."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "Deine Auktionspost nennt den anderen Spieler in diesem Client nicht (das Auktionshaus hält ihn anonym), also gibt es niemanden aufzulisten."
L["a list needs a name"] = "eine Liste braucht einen Namen"
L["a list with that name already exists"] = "eine Liste mit diesem Namen existiert bereits"
L["a week+"] = "eine Woche+"
L["above g"] = "über g"
L["announced %d, served %d, received %d, rejected %d"] = "%d angekündigt, %d geliefert, %d empfangen, %d abgelehnt"
L["auctionator history import"] = "Auctionator-Verlaufsimport"
L["average period"] = "Durchschnittszeitraum"
L["awaiting mail"] = "wartet auf Post"
L["backfill"] = "Backfill"
L["below g"] = "unter g"
L["blocked"] = "blockiert"
L["blocked %s"] = "%s blockiert"
L["bought"] = "gekauft"
L["chart library + window"] = "Chart-Bibliothek + Fenster"
L["codec+compress 6.4k items"] = "Codec+Kompression 6,4k Gegenstände"
L["could not load %s: %s"] = "%s konnte nicht geladen werden: %s"
L["could not load history addon"] = "Verlaufs-Addon konnte nicht geladen werden"
L["couldn't start an auction house search for %s"] = "Auktionshaussuche für %s konnte nicht gestartet werden"
L["data"] = "Daten"
L["deposit %s"] = "Anzahlung %s"
L["done %s"] = "fertig %s"
L["down  (wick = cheapest)"] = "runter  (Docht = günstigstes)"
L["dropped to %s (alert at %s)"] = "gefallen auf %s (Alarm bei %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "Kodieren %.0f ms, Komprimieren %.0f ms, Entpacken+Dekodieren %.0f ms, %d KB -> %d KB"
L["ended?"] = "beendet?"
L["enter a character name"] = "gib einen Charakternamen ein"
L["guild sync"] = "Gilden-Sync"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "Gilden-Sync: %s, %d angekündigt, %d geliefert, %d empfangen, %d abgelehnt"
L["history addon"] = "Verlaufs-Addon"
L["history import from Auctionator failed: %s"] = "Verlaufsimport aus Auctionator fehlgeschlagen: %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "Verlaufsimport aus Auctionator erfolgt nur im Auktionshaus deiner Fraktion (seine Daten mischen alle Häuser)."
L["history lookup (cold)"] = "Verlaufsabfrage (kalt)"
L["history: %d raw scans, %d days, %.0f KB"] = "Verlauf: %d Roh-Scans, %d Tage, %.0f KB"
L["imported %d days of price history from Auctionator into %s"] =
  "%d Tage Preisverlauf aus Auctionator in %s importiert"
L["item %d: %d points in %.1f ms"] = "Gegenstand %d: %d Punkte in %.1f ms"
L["item from latest scan has no daily points"] = "Gegenstand aus dem letzten Scan hat keine Tagespunkte"
L["item not loaded yet - try again in a moment"] = "Gegenstand noch nicht geladen - versuch es gleich noch mal"
L["just now"] = "gerade eben"
L["last full scan"] = "letzter vollständiger Scan"
L["last full scan: %d items, %s ago"] = "letzter vollständiger Scan: %d Gegenstände, vor %s"
L["last seen %s"] = "zuletzt gesehen %s"
L["libraries"] = "Bibliotheken"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] = "geladen in %s ms, %d Shard(s), %.0f KB Tagesverlauf"
L["loading history..."] = "lade Verlauf..."
L["loading item names %d/%d"] = "lade Gegenstandsnamen %d/%d"
L["lowest"] = "niedrigster"
L["margin %"] = "Marge %"
L["market"] = "Markt"
L["market index"] = "Marktindex"
L["market index failed:"] = "Marktindex fehlgeschlagen:"
L["max g"] = "max. g"
L["min g"] = "min. g"
L["never"] = "nie"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "noch kein vollständiger Scan erfasst: Öffne das AH und führe einen vollständigen Scan durch (mit deinem Scan-Addon oder dem des Spiels)"
L["no history for %s in %s"] = "kein Verlauf für %s in %s"
L["no scans in this shard yet"] = "noch keine Scans in diesem Shard"
L["none"] = "keine"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "noch keine: Öffne das AH und führe einen vollständigen Scan durch, dann starte /ame selftest erneut"
L["not in a guild"] = "nicht in einer Gilde"
L["not loaded"] = "nicht geladen"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "hier nichts importiert (nur mit Auctionator-Daten, im Auktionshaus deiner Fraktion)"
L["off"] = "aus"
L["on"] = "an"
L["on buy/sell signal"] = "bei Kauf-/Verkaufssignal"
L["on, but you're not in a guild"] = "an, aber du bist in keiner Gilde"
L["open the auction house first"] = "öffne zuerst das Auktionshaus"
L["profit g"] = "Gewinn g"
L["reading full scan (%d listings) in the background..."] = "lese vollständigen Scan (%d Angebote) im Hintergrund..."
L["received a full scan from %s via sync (%d items, %s)"] =
  "vollständigen Scan von %s per Sync empfangen (%d Gegenstände, %s)"
L["recorded full scan: %d items from %d listings (%s)"] =
  "vollständiger Scan erfasst: %d Gegenstände aus %d Angeboten (%s)"
L["rose to %s (alert at %s)"] = "gestiegen auf %s (Alarm bei %s)"
L["round trip mismatch"] = "Round-Trip-Abweichung"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "Scan-Pipeline: %d Anfragen, %d Events (%d seit letzter Anfrage), gelesen %s, abgebrochen %d; Ingest angefordert=%s liest=%s"
L["scan read failed:"] = "Scan-Lesen fehlgeschlagen:"
L["score"] = "Score"
L["score %+d"] = "Score %+d"
L["search"] = "suchen"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "Selbsttest abgeschlossen:\n%s\n\nUI jetzt neu laden, um die Ergebnisse zu speichern?"
L["selftest starting (this may pause the game for a moment)"] = "Selbsttest startet (das Spiel kann kurz stocken)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "Selbsttest: %d bestanden, %d Warnungen, %d fehlgeschlagen. Neu laden, um die Ergebnisse zu speichern (/reload)."
L["shard"] = "Shard"
L["shared"] = "geteilt"
L["sharing"] = "Teilen"
L["signal"] = "Signal"
L["sold"] = "verkauft"
L["storing %s scan failed:"] = "Speichern des %s-Scans fehlgeschlagen:"
L["supply"] = "Angebot"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "das AH wurde geschlossen, bevor AME den vollständigen Scan fertig gelesen hat; er wurde nicht erfasst."
L["today"] = "heute"
L["turned off in settings"] = "in den Einstellungen deaktiviert"
L["unknown command, try /ame help"] = "unbekannter Befehl, versuch /ame help"
L["unlikely to sell soon: consider holding"] = "verkauft sich wohl nicht bald: lieber halten"
L["up"] = "hoch"
L["usage: /ame item <item link or itemID>"] = "Verwendung: /ame item <Gegenstandslink oder Item-ID>"
L["volatility"] = "Volatilität"
L["waiting for them to approve"] = "wartet auf Zustimmung"
L["wants to share, %s"] = "möchte teilen, %s"
L["well below its usual price"] = "deutlich unter dem üblichen Preis"
L["wheel: zoom, drag: pan, double-click: reset"] = "Rad: Zoom, Ziehen: Verschieben, Doppelklick: Zurücksetzen"
L["whisper"] = "Flüstern"
L["window created, market tab rendered"] = "Fenster erstellt, Markt-Reiter gerendert"
L["yesterday"] = "gestern"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "du bist im Kauf-AH: Suchen (oder Shift-Klick auf eine Zeile) zum Kaufen"
L["~%d days"] = "~%d Tage"
L["~%dh"] = "~%d Std."
