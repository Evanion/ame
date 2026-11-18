-- Italian. Keys are the English texts (Locales/enUS.lua);
-- anything not translated here falls back to English.
-- Translations are AI-made: native speakers, please review (CurseForge's translation tool, or a pull request).
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:NewLocale(ADDON, "itIT")
if not L then
  return
end

L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "%d vendite e acquisti alla casa d'aste negli ultimi 90 giorni. AME li registra dalla posta delle aste: apri la cassetta delle lettere per raccogliere i nuovi."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "%d aste attive sui tuoi personaggi, all'ultima apertura della casa d'aste di ciascuno. Le vendite compaiono subito nel registro e vengono saldate all'arrivo della posta delle aste."
L["%d ahead"] = "%d davanti"
L["%d auctions"] = "%d aste"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "%d clienti negli ultimi 90 giorni, per oro speso con te (dalla posta delle aste)."
L["%d days"] = "%d giorni"
L["%d days ago"] = "%d giorni fa"
L["%d h ago"] = "%d h fa"
L["%d h listings"] = "inserzioni da %d h"
L["%d items"] = "%d oggetti"
L["%d items  ·  showing %d-%d  ·  index from %s"] = "%d oggetti  ·  mostrati %d-%d  ·  indice da %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d oggetti da %s inserzioni, salvati %s ms dopo la richiesta di scansione"
L["%d items not searchable yet (names loading)"] = "%d oggetti non ancora cercabili (caricamento nomi)"
L["%d items summarized"] = "%d oggetti riepilogati"
L["%d items summarized in %s ms wall"] = "%d oggetti riepilogati in %s ms (tempo reale)"
L["%d min ago"] = "%d min fa"
L["%d of %d known prices differ more than %dx from ours"] = "%d prezzi noti su %d differiscono più di %dx dai nostri"
L["%d outlier price ignored"] = "%d prezzo anomalo ignorato"
L["%d outlier prices ignored"] = "%d prezzi anomali ignorati"
L["%d passed, %d warnings, %d failed"] = "%d superati, %d avvisi, %d falliti"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posizioni su %d personaggio. Le borse si aggiornano mentre giochi; apri la banca e la casa d'aste per includere gli oggetti in banca e le aste attive."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posizioni su %d personaggi. Le borse si aggiornano mentre giochi; apri la banca e la casa d'aste per includere gli oggetti in banca e le aste attive."
L["%d scans in 7 days"] = "%d scansioni in 7 giorni"
L["%d scans/7d, %s"] = "%d scansioni/7g, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "%d fornitori negli ultimi 90 giorni, per oro che hai speso con loro (dalla posta delle aste)."
L["%d watched items have no price history here yet"] = "%d oggetti osservati non hanno ancora uno storico prezzi qui"
L["%d-day average"] = "Media a %d giorni"
L["%dd avg"] = "media %dg"
L["%dx off usual"] = "%dx dal solito"
L["%s %s: min %s, market %s, qty %d (%d samples)"] = "%s %s: min %s, mercato %s, qtà %d (%d campioni)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s ultimo (%s): min %s, mercato %s, %d unità in %d aste"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s vuole condividere con te i prezzi delle aste. Apri |cffffffff/ame|r > Sync per approvare."
L["(each point is one scan)"] = "(ogni punto è una scansione)"
L["(est.)"] = "(stima)"
L["(needs LibDBIcon; included in releases)"] = "(richiede LibDBIcon; incluso nelle release)"
L["+ %d more"] = "+ altri %d"
L[", %d scans received"] = ", %d scansioni ricevute"
L["...and close it when the auction house closes"] = "...e chiudilo quando si chiude la casa d'aste"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Shift-click an item with the window open - chart it"] =
  "/ame - apri la finestra  ·  /ame <link oggetto> - grafico di un oggetto  ·  Maiusc-clic su un oggetto a finestra aperta - il suo grafico"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - apri la finestra.   /ame <link oggetto> - grafico di un oggetto.   /ame status - stato di dati e sync.   /ame config - impostazioni.   /ame selftest - verifica che tutto funzioni."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <link> - stampa lo storico  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/sett."
L["1 day"] = "1 giorno"
L["30 days: sold / bought"] = "30 giorni: venduto / comprato"
L["7-day change"] = "Variazione 7 g"
L["7d"] = "7g"
L["7d average"] = "Media 7 giorni"
L["7d avg"] = "Media 7g"
L["7d change"] = "Var. 7g"
L["<1h"] = "<1 h"
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Uno screener su tutti gli oggetti con uno storico. Scegli una categoria o una watchlist a sinistra, cerca per nome, filtra per qualità, fascia di prezzo o segnale e clicca una colonna per ordinare. Passa sopra l'intestazione di una colonna per sapere cosa significa. Clicca una riga per aprirne il grafico; clicca la stella per osservarlo."
L["AH cut"] = "Commissione"
L["AME alert: %s %s"] = "Avviso AME: %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "AME ascolta le API della casa d'aste del gioco stesso, quindi ogni scansione e ricerca che fai viene registrata - dalla finestra predefinita della casa d'aste o da qualsiasi addon di scansione (funziona bene con addon come Auctionator). Non viene scansionato nulla in più. Lo storico è tenuto per mercato (reame o regole Forever) e per casa d'aste, e i membri della gilda che usano AME condividono automaticamente le loro scansioni complete."
L["API + database found"] = "API + database trovati"
L["API found, database not readable (no backfill)"] = "API trovata, database non leggibile (niente backfill)"
L["Accept"] = "Accetta"
L["AceComm not available: sync disabled"] = "AceComm non disponibile: sync disattivata"
L["Activity"] = "Attività"
L["Add"] = "Aggiungi"
L["Add to a watchlist"] = "Aggiungi a una watchlist"
L["Alert when"] = "Avvisa quando"
L["Alert:"] = "Avviso:"
L["All"] = "Tutti"
L["All items"] = "Tutti gli oggetti"
L["All markets: %d, %.0f KB of compressed daily history"] =
  "Tutti i mercati: %d, %.0f KB di storico giornaliero compresso"
L["All of AME's settings are in its own window: %s, Settings tab."] =
  "Tutte le impostazioni di AME sono nella sua finestra: %s, scheda Impostazioni."
L["Alliance AH"] = "CdA Alleanza"
L["Alliance blue"] = "Blu Alleanza"
L["Alt+Shift-click"] = "Alt+Maiusc-clic"
L["Alt-click"] = "Alt-clic"
L["Always show full tooltip details (otherwise hold Shift)"] =
  "Mostra sempre tutti i dettagli nel tooltip (altrimenti tieni premuto Maiusc)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Una classifica di opportunità da -100 a +100. Più è alta, più l'oggetto è sotto il suo prezzo abituale, stabile e in tendenza rialzista. Intorno a 0 il prezzo è normale; negativo significa più caro del solito. Ordina per questo valore per trovare in fretta gli affari."
L["Announce recorded full scans in chat"] = "Annuncia in chat le scansioni complete registrate"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "Annunciate %d volte, %d scansioni servite, %d ricevute, %d rifiutate"
L["Any age"] = "Qualsiasi età"
L["Any quality"] = "Qualsiasi qualità"
L["Approve"] = "Approva"
L["Arbitrage"] = "Arbitraggio"
L["Arbitrage tab"] = "Scheda Arbitraggio"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "Hai chiesto a %s di condividere. Vedrà una richiesta nella sua scheda Sync."
L["Asking prices"] = "Prezzi richiesti"
L["At market price"] = "A prezzo di mercato"
L["Auction house"] = "Casa d'aste"
L["Auction house cut"] = "Commissione della casa d'aste"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator non installato: niente da importare (le scansioni vengono comunque registrate dal gioco)"
L["Auctions"] = "Aste"
L["Average"] = "Media"
L["Average cost"] = "Costo medio"
L["Avg cost"] = "Costo medio"
L["Azeroth Mercantile Exchange %s  ·  created by Tyken Evanion  ·  PvP Horde, WoW Forever"] =
  "Azeroth Mercantile Exchange %s  ·  creato da Tyken Evanion  ·  PvP Orda, WoW Forever"
L["BUY"] = "COMPRA"
L["BUY signal at %s"] = "Segnale COMPRA a %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  "COMPRA: il prezzo di oggi è insolitamente basso per questo oggetto - almeno 1,5 deviazioni standard sotto la sua media a 30 giorni. VENDI: insolitamente alto secondo la stessa misura. TIENI: nel suo intervallo normale - tienilo se lo possiedi, nessun vantaggio a comprare. ATTENDI: economico, ma i venditori stanno svendendo - aspetta il minimo. Servono 7+ giorni di storico (\"-\" fino ad allora). La fase di mercato confronta il movimento di prezzo della settimana con l'offerta: scarsità, domanda stabile, venditori in arrivo, restringimento, equilibrio, pressione in aumento, venditori in ritirata, domanda debole o svendita. Il segnale confronta l'oggetto con se stesso; è un indizio, non una consulenza finanziaria."
L["Balanced"] = "Equilibrio"
L["Block"] = "Blocca"
L["Blocked"] = "Bloccato"
L["Building market index..."] = "Costruzione indice di mercato..."
L["Buy at"] = "Compra a"
L["By your guild officers: %s"] = "Dagli ufficiali della tua gilda: %s"
L["Cancel"] = "Annulla"
L["Candles"] = "Candele"
L["Character"] = "Personaggio"
L["Character name, e.g. First Last"] = "Nome del personaggio, es. Nome Cognome"
L["Chart style"] = "Stile del grafico"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Controlla ogni parte di AME e propone un ricaricamento per salvare i risultati."
L["Class %d"] = "Classe %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Clicca una riga per aprirne il grafico dei prezzi. Clicca la stella per aggiungerlo a una watchlist. Le barre dopo il nome mostrano quanto fidarsi dei numeri: 3 verdi = molte scansioni recenti, 2 gialle = alcune, 1 rossa = poche o vecchie."
L["Close"] = "Chiudi"
L["Commands"] = "Comandi"
L["Common+"] = "Comune+"
L["Copy to my watchlists"] = "Copia nelle mie watchlist"
L["Could not load history: %s"] = "Impossibile caricare lo storico: %s"
L["Ctrl+Alt-click"] = "Ctrl+Alt-clic"
L["Customers"] = "Clienti"
L["Data"] = "Dati"
L["Data quality"] = "Qualità dei dati"
L["Days to sell"] = "Giorni per vendere"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "I giorni in cui il prezzo di un oggetto è questo numero di volte sopra (o sotto) i giorni vicini vengono esclusi da screener, segnali, avvisi e grafici - di solito un singolo annuncio rincarato del 1000% messo in vendita in un mercato poco liquido. All'interno di una scansione completa, AME ignora già le inserzioni care: il prezzo di mercato usa la parte più economica dell'offerta."
L["Decline"] = "Rifiuta"
L["Delete"] = "Elimina"
L["Delete list..."] = "Elimina lista..."
L['Delete the watchlist "%s"?'] = 'Eliminare la watchlist "%s"?'
L["Deposit"] = "Deposito"
L["Deposits for"] = "Depositi per"
L["Depth"] = "Profondità"
L["Display"] = "Visualizzazione"
L["Dock AME beside the auction house when there's room"] = "Aggancia AME accanto alla casa d'aste quando c'è spazio"
L["Dumping"] = "Svendita"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Ogni candela copre uno o più giorni. Apre alla chiusura della candela precedente e chiude al prezzo di mercato; verde ha chiuso più in alto, rossa più in basso. L'ombra sottile scende fino all'inserzione più economica vista."
L["Epic+"] = "Epico+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Unità vendute al giorno stimate dove venderesti. Confrontale con quante ne vuoi comprare: se se ne vendono 5 al giorno, 100 richiederanno settimane."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Tutto ciò che possiedono i tuoi personaggi - borse, banca e aste attive - al prezzo di mercato della casa d'aste della tua fazione. Oggetti in banca e aste sono contati all'ultima apertura della banca / della casa d'aste."
L["Faction auction houses"] = "Case d'aste di fazione"
L["Follow market"] = "Segui il mercato"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Per le unità comprate alla casa d'aste: quanto valgono ora a prezzo di mercato meno quanto hai pagato. Diventa profitto reale quando vendi."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "Dalle tue vendite all'asta: quanto hai ricevuto dopo la commissione, meno quanto hai pagato per quelle unità (prima gli acquisti più vecchi). Le vendite di oggetti raccolti o creati contano per intero."
L["Goblin AH"] = "CdA goblin"
L["Goblin auction houses"] = "Case d'aste goblin"
L["Goblin gold"] = "Oro goblin"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Oro ricevuto dalle vendite all'asta (dopo la commissione) e oro speso in acquisti all'asta negli ultimi 30 giorni."
L["Guide"] = "Guida"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Gli ufficiali di gilda possono bloccare giocatori per tutti: aggiungi una riga "%s" alle informazioni di gilda.'
L["Guild watchlists"] = "Watchlist della gilda"
L["Guild: %s"] = "Gilda: %s"
L["HOLD"] = "TIENI"
L["Held"] = "Possedute"
L["High"] = "Massimo"
L["History not loaded yet."] = "Storico non ancora caricato."
L["Hold Shift for more AME data"] = "Tieni premuto Maiusc per altri dati AME"
L["Holdings value"] = "Valore dei possedimenti"
L["Horde AH"] = "CdA Orda"
L["Horde red"] = "Rosso Orda"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "Quanto velocemente si muove l'oggetto: unità sparite tra scansioni complete consecutive di questa casa d'aste, al giorno, nell'ultima settimana. Conta inserzioni vendute, annullate e scadute, e le nuove inserzioni nascondono alcune vendite, quindi prendilo come un'indicazione di massima. Un oggetto economico che non si vende mai è una trappola; un numero alto significa che puoi vendere una pila in fretta. Servono alcune scansioni complete nello stesso giorno."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Quanto tempo ci vorrebbe per vendere tutto ciò che possiedi al ritmo di vendita attuale dell'oggetto (stima)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Quanti ne sono in vendita nei dati più recenti. Nella pagina dell'oggetto il valore in % nella stessa casella è l'andamento settimanale dell'offerta: un'offerta in calo spesso precede un aumento dei prezzi."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Quante unità puoi comprare alla casa d'aste di acquisto prima che la rotta smetta di rendere, e il profitto totale: ogni inserzione con prezzo sotto quanto se ne ricava vendendone una dopo la commissione. Servono le inserzioni dell'oggetto, quindi cercalo prima alla casa d'aste di acquisto (lo fa il pulsante Cerca) - poi restano per 6 ore. Vendere così tanto richiede comunque tempo: controlla Vend./g."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "Quanto si è mosso il prezzo di mercato rispetto ai dati di 7 giorni fa. Verde è in salita, rosso in discesa."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "Quanto salta il prezzo da un giorno all'altro (la dispersione delle variazioni giornaliere in % calcolata su 30 giorni). Numeri bassi indicano un oggetto stabile e prevedibile; numeri alti oscillazioni rischiose - e opportunità più grandi."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "Quanto è vecchio il più vecchio dei due prezzi. Dati freschi su entrambi i lati rendono una rotta affidabile - scansiona entrambe le case d'aste (gli alt di questo account contano) prima di comprare."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Se Auctionator è installato: importa i suoi prezzi giornalieri recenti per i giorni in cui AME non ha dati (CdA di fazione)."
L["Ignore outrageous prices"] = "Ignora prezzi assurdi"
L["Import history from Auctionator"] = "Importa lo storico da Auctionator"
L["Item"] = "Oggetto"
L["Item name, ID, or Shift-click an item"] = "Nome, ID o Maiusc-clic su un oggetto"
L["Item tab"] = "Scheda Oggetto"
L["Items"] = "Oggetti"
L["Items tracked"] = "Oggetti tracciati"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Oggetti che puoi comprare in una casa d'aste e rivendere in un'altra con profitto dopo la commissione - es. la casa d'aste della tua fazione e quella goblin (interfazione). Ogni casa d'aste ha il suo storico, quindi scansionale entrambe (gli alt di questo account contano). Passa sopra le colonne per i dettagli."
L['Keep the AH open until AME says "recorded full scan".'] =
  'Tieni aperta la casa d\'aste finché AME non dice "scansione completa registrata".'
L["Last"] = "Ultimo"
L["Last full scan"] = "Ultima scansione completa"
L["Last full scan: %d items, %s"] = "Ultima scansione completa: %d oggetti, %s"
L["Last received: %d items from %s, %s"] = "Ultima ricezione: %d oggetti da %s, %s"
L["Last rejected:"] = "Ultimo rifiuto:"
L["Ledger"] = "Registro"
L["Left-click: window   Right-click: settings"] = "Clic sinistro: finestra   Clic destro: impostazioni"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 non caricata"
L["LibDeflate not loaded"] = "LibDeflate non caricata"
L["Line"] = "Linea"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "In vendita alla CdA di acquisto / alla CdA di vendita. L'ideale è tanto da comprare e poca concorrenza dove vendi; un grande divario su una sola inserzione alla CdA di acquisto può sparire in fretta."
L["Listed on the AH now"] = "In vendita ora alla CdA"
L["Listed on the auction house now"] = "In vendita ora alla casa d'aste"
L["Loading history..."] = "Caricamento storico..."
L["Loading market data..."] = "Caricamento dati di mercato..."
L["Loading recent scans..."] = "Caricamento scansioni recenti..."
L["Low (cheapest)"] = "Minimo (più economico)"
L["Lowest"] = "Più basso"
L["Margin"] = "Margine"
L["Market"] = "Mercato"
L["Market price"] = "Prezzo di mercato"
L["Market tab"] = "Scheda Mercato"
L["Market: %s"] = "Mercato: %s"
L["Mostly"] = "Per lo più"
L["Name for the new watchlist:"] = "Nome della nuova watchlist:"
L["New list"] = "Nuova lista"
L["New list..."] = "Nuova lista..."
L["No full scan recorded yet."] = "Nessuna scansione completa registrata."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Ancora nessuno storico per questo oggetto. Cercalo alla casa d'aste o esegui una scansione completa."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Ancora nessun dato di mercato per la casa d'aste della tua fazione - scansiona lì per valutare i tuoi possedimenti."
L["No one yet."] = "Ancora nessuno."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Ancora nessuno storico prezzi per la %s: scansiona lì (vale qualsiasi personaggio di questo account) per confrontare."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Ancora nessuno storico prezzi per la %s: scansiona lì (vale qualsiasi personaggio di questo account)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "Nessuna scansione di questo oggetto negli ultimi 2 giorni. Lo storico giornaliero è negli altri intervalli."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Ancora nessuno. Aggiungi un amico qui sopra - anche lui deve avere AME e deve approvare."
L["Normal %s"] = "Normale %s"
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Ancora nulla ricevuto - le scansioni arrivano quando qualcuno con cui condividi esegue una scansione completa."
L["Notifications"] = "Notifiche"
L["Off"] = "Disattivato"
L["Off by default: loot and raid addons (e.g. Gargul, AHDB) use modified clicks on items and links. With the AME window open, Shift-click an item to chart it."] =
  "Disattivato di default: gli addon di bottino e incursione (es. Gargul, AHDB) usano i clic con modificatore su oggetti e link. Con la finestra di AME aperta, Maiusc-clic su un oggetto per vederne il grafico."
L["On a watchlist - click to change"] = "In una watchlist - clicca per cambiare"
L["Open"] = "Apertura"
L["Open AME settings"] = "Apri impostazioni di AME"
L["Open AME together with the auction house"] = "Apri AME insieme alla casa d'aste"
L["Open item charts with"] = "Apri i grafici degli oggetti con"
L["Patient %s"] = "Paziente %s"
L["Per item: what it sells for, minus the AH cut, minus what you paid."] =
  "Per oggetto: il prezzo di vendita, meno la commissione della casa d'aste, meno quanto hai pagato."
L["Pick two different auction houses."] = "Scegli due case d'aste diverse."
L["Play a sound when a watchlist alert fires"] = "Riproduci un suono quando scatta un avviso della watchlist"
L["Player"] = "Giocatore"
L["Portfolio"] = "Portafoglio"
L["Portfolio tab"] = "Scheda Portafoglio"
L["Positions"] = "Posizioni"
L["Post at"] = "Metti a"
L["Posting price"] = "Prezzo d'inserzione"
L["Posting price: not enough data on this item yet."] =
  "Prezzo d'inserzione: dati ancora insufficienti su questo oggetto."
L["Pressure building"] = "Pressione in aumento"
L["Price"] = "Prezzo"
L["Price each"] = "Prezzo cad."
L["Profit"] = "Profitto"
L["Profit as a share of what you paid. 50% means every 10g spent comes back as 15g."] =
  "Il profitto in rapporto a quanto hai pagato. 50% significa che ogni 10 o spesi tornano come 15 o."
L["Purchases"] = "Acquisti"
L["Qty"] = "Qtà"
L["Quick %s"] = "Rapido %s"
L["Rare+"] = "Raro+"
L["Reading the numbers"] = "Leggere i numeri"
L["Realized profit"] = "Profitto realizzato"
L["Realized profit, 7 days"] = "Profitto realizzato, 7 giorni"
L["Rebuild market index"] = "Ricostruisci indice di mercato"
L["Recently heard from"] = "Sentiti di recente"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Ricalcola i riepiloghi a 30 giorni usati da screener, tooltip e avvisi."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Registra i prezzi della casa d'aste da ogni scansione e ricerca che fai (API native; funziona con qualsiasi addon di scansione), per reame e casa d'aste."
L["Reload UI"] = "Ricarica interfaccia"
L["Requests"] = "Richieste"
L["Run self-test"] = "Esegui autotest"
L["SELL"] = "VENDI"
L["SELL signal at %s"] = "Segnale VENDI a %s"
L["Score"] = "Punteggio"
L["Search"] = "Cerca"
L["Search items..."] = "Cerca oggetti..."
L["Seen in 3 days"] = "Visto in 3 giorni"
L["Seen in 7 days"] = "Visto in 7 giorni"
L["Seen today/yesterday"] = "Visto oggi/ieri"
L["Sell at"] = "Vendi a"
L["Sellers piling in"] = "Venditori in arrivo"
L["Sellers withdrawing"] = "Venditori in ritirata"
L["Sells for"] = "Si vende a"
L["Sells per day (estimate)"] = "Vendite al giorno (stima)"
L["Sells per day at the sell house"] = "Vendite al giorno alla CdA di vendita"
L["Sells/d"] = "Vend./g"
L["Settings"] = "Impostazioni"
L["Share full scans with my guild (members running AME)"] =
  "Condividi le scansioni complete con la mia gilda (membri con AME)"
L["Share with guild"] = "Condividi con la gilda"
L["Share with trusted players (below)"] = "Condividi con i giocatori fidati (sotto)"
L["Sharing"] = "Condivisione"
L["Sharing settings are on the Sync tab."] = "Le impostazioni di condivisione sono nella scheda Sync."
L["Shift-click to search the auction house"] = "Maiusc-clic per cercare alla casa d'aste"
L["Shortage"] = "Scarsità"
L["Show AME prices in item tooltips"] = "Mostra i prezzi AME nei tooltip degli oggetti"
L["Show minimap button"] = "Mostra il pulsante della minimappa"
L["Signal"] = "Segnale"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Segnali e punteggio confrontano un oggetto con il suo stesso storico, quindi servono una settimana o più di dati perché abbiano senso. Gli oggetti economici E stabili (bassa volatilità) hanno il punteggio più alto. Un'offerta in calo con prezzo piatto è spesso un buon segnale precoce. Niente di tutto questo è un consiglio - i mercati possono restare strani per un po'."
L["Sold / bought"] = "Venduto / comprato"
L["Spent with you"] = "Speso da te"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  'Clicca la stella sugli oggetti per metterli in una watchlist; crea altre liste con "+ Nuova lista" nella barra laterale (clic destro su una lista per condividerla con la gilda o eliminarla; le liste condivise dai membri della gilda appaiono sotto le tue). Nella pagina di un oggetto imposta un avviso: sotto o sopra un prezzo in oro, o quando compare un segnale di acquisto/vendita. Gli avvisi vengono controllati dopo ogni scansione e annunciati in chat con un suono.'
L["Steady demand"] = "Domanda stabile"
L["Suppliers"] = "Fornitori"
L["Supply"] = "Offerta"
L["Supply  ·  sells/day"] = "Offerta  ·  vendite/giorno"
L["Swap"] = "Inverti"
L["Switch to the Item tab when you put an item up for sale"] =
  "Passa alla scheda Oggetto quando metti in vendita un oggetto"
L["Sync"] = "Sync"
L["Sync is unavailable: the AceComm library didn't load."] =
  "Sync non disponibile: la libreria AceComm non è stata caricata."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "Il prezzo di mercato giornaliero medio sul periodo scelto (Impostazioni > Periodo della media, 7 giorni di default). Confrontalo con il prezzo di mercato di oggi per vedere se l'oggetto è economico o caro in questo momento."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "L'inserzione più economica alla casa d'aste dove compri - quanto ti costano le prime unità."
L["The cheapest single listing seen in the latest data."] =
  "L'inserzione singola più economica vista negli ultimi dati."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "Il prezzo di mercato alla casa d'aste dove vendi: quanto si vende di solito l'oggetto lì."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Shift-click any item (bags, chat, the AH) while this window is open to chart it, or set a modifier click in Settings."] =
  "Il grafico dei prezzi: prezzo di mercato, inserzione più bassa, media a 7 giorni e offerta. Passa alle candele per una vista da trading. La rotellina fa zoom, trascinare sposta, doppio clic ripristina. Maiusc-clic su qualsiasi oggetto (borse, chat, casa d'aste) con questa finestra aperta per vederne il grafico, o imposta un clic con modificatore in Impostazioni."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Questo mercato: %d giorni di storico, %d scansioni recenti conservate per intero"
L["Tightening"] = "Restringimento"
L["Time left"] = "Tempo rimasto"
L["Top buy signals"] = "Migliori segnali d'acquisto"
L["Total"] = "Totale"
L["Trusted"] = "Fidato"
L["Trusted (%d)"] = "Fidati (%d)"
L["Trusted players"] = "Giocatori fidati"
L["Type %d"] = "Tipo %d"
L["Unblock"] = "Sblocca"
L["Uncommon+"] = "Non comune+"
L["Unrealized"] = "Non realizz."
L["Unrealized profit"] = "Profitto non realizzato"
L["VENDOR"] = "MERCANTE"
L["VENDOR: after the AH cut and the listing deposit, the auction house pays less than a vendor would - sell it to a vendor."] =
  "MERCANTE: dopo la commissione e il deposito, la casa d'aste rende meno di un mercante - vendilo a un mercante."
L["Value"] = "Valore"
L["Volatility"] = "Volatilità"
L["WAIT"] = "ATTENDI"
L["Watch"] = "Osserva"
L["Watching"] = "Osservato"
L["Watchlists and alerts"] = "Watchlist e avvisi"
L["Weak demand"] = "Domanda debole"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "Ciò che possiedono tutti i tuoi personaggi, valutato al mercato della tua fazione, con costo e profitto non realizzato per ciò che hai comprato alla casa d'aste, il segnale Compra/Tieni/Vendi e quanto tempo servirebbe per vendere. Il registro elenca le tue vendite e i tuoi acquisti alla casa d'aste - registrati dalla posta delle aste quando apri la cassetta delle lettere."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Quanto costa in anticipo mettere in vendita un'unità alla CdA di vendita: una quota del prezzo di vendita al mercante dell'oggetto (CdA di fazione 5/20/60% fissati per 2/8/24 ore, CdA goblin cinque volte tanto), almeno 1 argento. Ti viene restituito se si vende e lo perdi se non si vende - quindi un deposito alto su un oggetto che si vende lentamente è un rischio reale."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "Quanto si vende di solito l'oggetto in questo momento. Dai dati completi delle inserzioni è la media del 15-30% offerto al prezzo più basso nella casa d'aste, che ignora alcune inserzioni stracciate o assurde. Da un riepilogo di navigazione (quello che molti scanner fanno di default) si conosce solo l'inserzione più economica, quindi è il prezzo più basso."
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "A che prezzo mettere all'asta perché venda entro la durata dell'inserzione, invece di stare 1 rame sotto l'inserzione più economica. Gli acquirenti prendono prima le inserzioni più economiche, quindi AME conta le unità davanti a te a ogni prezzo, quanto velocemente si vende l'oggetto e quanto spesso nuove inserzioni vanno sotto il tuo prezzo, e pesa la probabilità di vendere contro il deposito che perdi se non vende. Rapido vende quasi sicuramente entro poche ore, Normale è il prezzo migliore per la probabilità, Paziente è il prezzo più alto che vende ancora circa metà delle volte. AME impara l'andamento di ogni oggetto dalle tue scansioni (ore di punta, giorni della settimana, quanto competono i venditori) e dalle tue inserzioni: se gli oggetti scadono spesso ai suoi prezzi, diventa più prudente per quell'oggetto. Con pochi dati si basa su oggetti simili; le barre mostrano quanto sa."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Quanto hai pagato per unità per le unità comprate alla casa d'aste (gli acquisti più vecchi vengono venduti per primi). Gli oggetti raccolti o creati non hanno costo."
L["When"] = "Quando"
L["Where the data comes from"] = "Da dove vengono i dati"
L["Window colours"] = "Colori della finestra"
L["Window scale"] = "Scala della finestra"
L["You haven't blocked anyone."] = "Non hai bloccato nessuno."
L["You spent"] = "Hai speso"
L["You'd receive (after the cut)"] = "Riceveresti (dopo la commissione)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Le tue aste attive su tutti i personaggi, all'ultima apertura della casa d'aste di ciascuno."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "I tuoi alt su questo account Battle.net condividono già tutto: lo storico di AME è salvato per l'intero account. Dai fiducia ai giocatori per scambiare scansioni con amici, o con i tuoi personaggi su altri account. Vengono condivisi solo il tuo mercato e la tua casa d'aste, e le scansioni molto diverse dai tuoi prezzi vengono rifiutate."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "La posta delle aste non nomina l'altro giocatore su questo client (la casa d'aste lo mantiene anonimo), quindi non c'è nessuno da elencare."
L["a list needs a name"] = "una lista ha bisogno di un nome"
L["a list with that name already exists"] = "esiste già una lista con quel nome"
L["a week+"] = "una settimana+"
L["above g"] = "sopra (o)"
L["announced %d, served %d, received %d, rejected %d"] = "annunciate %d, servite %d, ricevute %d, rifiutate %d"
L["auctionator history import"] = "importazione storico Auctionator"
L["average period"] = "periodo della media"
L["awaiting mail"] = "in attesa di posta"
L["backfill"] = "backfill"
L["background jobs: %s"] = "attività in background: %s"
L["below g"] = "sotto (o)"
L["blocked"] = "bloccato"
L["blocked %s"] = "%s bloccato"
L["bought"] = "comprato"
L["chart library + window"] = "libreria grafici + finestra"
L["codec+compress 6.4k items"] = "codec+compressione 6,4k oggetti"
L["could not load %s: %s"] = "impossibile caricare %s: %s"
L["could not load history addon"] = "impossibile caricare l'addon dello storico"
L["couldn't start an auction house search for %s"] = "impossibile avviare una ricerca alla casa d'aste per %s"
L["data"] = "dati"
L["done %s"] = "fatto %s"
L["dropped to %s (alert at %s)"] = "sceso a %s (avviso a %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "codifica %.0f ms, compressione %.0f ms, decompressione+decodifica %.0f ms, %d KB -> %d KB"
L["ended?"] = "terminata?"
L["enter a character name"] = "inserisci il nome di un personaggio"
L["guild"] = "gilda"
L["guild sync"] = "sync di gilda"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "sync di gilda: %s, annunciate %d, servite %d, ricevute %d, rifiutate %d"
L["heard %s"] = "ultimo contatto: %s"
L["history addon"] = "addon dello storico"
L["history import from Auctionator failed: %s"] = "importazione dello storico da Auctionator fallita: %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "l'importazione dello storico da Auctionator si fa solo alla casa d'aste della tua fazione (i suoi dati mescolano tutte le case)."
L["history lookup (cold)"] = "ricerca storico (a freddo)"
L["history: %d raw scans, %d days, %.0f KB"] = "storico: %d scansioni grezze, %d giorni, %.0f KB"
L["idle"] = "nessuna"
L["imported %d days of price history from Auctionator into %s"] =
  "importati %d giorni di storico prezzi da Auctionator in %s"
L["item %d: %d points in %.1f ms"] = "oggetto %d: %d punti in %.1f ms"
L["item from latest scan has no daily points"] = "l'oggetto dell'ultima scansione non ha punti giornalieri"
L["item not loaded yet - try again in a moment"] = "oggetto non ancora caricato - riprova tra un attimo"
L["just now"] = "proprio ora"
L["last error (%s, %s): %s"] = "ultimo errore (%s, %s): %s"
L["last full scan"] = "ultima scansione completa"
L["last full scan: %d items, %s ago"] = "ultima scansione completa: %d oggetti, %s fa"
L["last seen %s"] = "visto l'ultima volta %s"
L["libraries"] = "librerie"
L["listed"] = "in vendita"
L["loaded"] = "caricato"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] =
  "caricato in %s ms, %d shard, %.0f KB di storico giornaliero"
L["loading history..."] = "caricamento storico..."
L["loading item names %d/%d"] = "caricamento nomi oggetti %d/%d"
L["lowest"] = "più basso"
L["margin %"] = "margine %"
L["market"] = "mercato"
L["market %s, history %s"] = "mercato %s, storico %s"
L["market index"] = "indice di mercato"
L["max g"] = "max (o)"
L["min g"] = "min (o)"
L["more is listed than sells in one listing time: only the lowest price sells soon"] =
  "in vendita più di quanto si vende in una durata d'inserzione: solo il prezzo più basso venderà presto"
L["never"] = "mai"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "nessuna scansione completa registrata: apri la casa d'aste ed esegui una scansione completa (del tuo addon di scansione o del gioco)"
L["no history for %s in %s"] = "nessuno storico per %s in %s"
L["no scans in this shard yet"] = "ancora nessuna scansione in questo shard"
L["none"] = "nessuno"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "ancora nessuna: apri la casa d'aste ed esegui una scansione completa, poi riesegui /ame selftest"
L["not built yet (needs history)"] = "non ancora costruito (serve lo storico)"
L["not heard yet"] = "nessun contatto finora"
L["not in a guild"] = "non in una gilda"
L["not loaded"] = "non caricato"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "qui non è stato importato nulla (solo con i dati di Auctionator, alla casa d'aste della tua fazione)"
L["off"] = "off"
L["on"] = "on"
L["on buy/sell signal"] = "a segnale di compra/vendi"
L["on, but you're not in a guild"] = "on, ma non sei in una gilda"
L["open the auction house first"] = "apri prima la casa d'aste"
L["profit g"] = "profitto (o)"
L["reading full scan (%d listings) in the background..."] =
  "lettura della scansione completa (%d inserzioni) in background..."
L["received a full scan from %s via sync (%d items, %s)"] =
  "ricevuta una scansione completa da %s via sync (%d oggetti, %s)"
L["recorded full scan: %d items from %d listings (%s)"] =
  "scansione completa registrata: %d oggetti da %d inserzioni (%s)"
L["rose to %s (alert at %s)"] = "salito a %s (avviso a %s)"
L["round trip mismatch"] = "discrepanza andata/ritorno"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "pipeline di scansione: %d richieste, %d eventi (%d dall'ultima richiesta), letto %s, interrotte %d; acquisizione richiesta=%s lettura=%s"
L["scan read failed:"] = "lettura della scansione fallita:"
L["score"] = "punteggio"
L["score %+d"] = "punteggio %+d"
L["search"] = "cerca"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "autotest finito:\n%s\n\nRicaricare ora l'interfaccia per salvare i risultati?"
L["selftest starting (this may pause the game for a moment)"] =
  "autotest in avvio (il gioco potrebbe bloccarsi per un momento)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "autotest: %d superati, %d avvisi, %d falliti. Ricarica per salvare i risultati (/reload)."
L["sells"] = "vendite"
L["shard"] = "shard"
L["shared"] = "condivisa"
L["sharing"] = "condivisione"
L["signal"] = "segnale"
L["sold"] = "venduto"
L["still building in the background"] = "ancora in costruzione in background"
L["storing %s scan failed:"] = "salvataggio della scansione %s fallito:"
L["supply"] = "offerta"
L["sync errors: %d (last: %s)"] = "errori di sync: %d (ultimo: %s)"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "la casa d'aste è stata chiusa prima che AME finisse di leggere la scansione completa; non è stata registrata."
L["today"] = "oggi"
L["turned off in settings"] = "disattivato nelle impostazioni"
L["unknown command, try /ame help"] = "comando sconosciuto, prova /ame help"
L["unlikely to sell soon: consider holding"] = "difficile che venda presto: valuta di tenerlo"
L["up"] = "su"
L["updating market data..."] = "aggiornamento dati di mercato..."
L["usage: /ame item <item link or itemID>"] = "uso: /ame item <link oggetto o ID oggetto>"
L["via %s, %s"] = "via %s, %s"
L["volatility"] = "volatilità"
L["waiting for them to approve"] = "in attesa della sua approvazione"
L["wants to share, %s"] = "vuole condividere, %s"
L["well below its usual price"] = "molto sotto il suo prezzo abituale"
L["whisper"] = "sussurro"
L["window created, market tab rendered"] = "finestra creata, scheda Mercato disegnata"
L["yesterday"] = "ieri"
L["you bought"] = "i tuoi acquisti"
L["you sold"] = "le tue vendite"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "sei alla CdA di acquisto: Cerca (o Maiusc-clic su una riga) per comprare"
L["~%d days"] = "~%d giorni"
L["~%dh"] = "~%d h"
