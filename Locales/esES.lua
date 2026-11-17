-- Spanish (Spain and Latin America). Keys are the English texts (see Locales/enUS.lua); anything not translated
-- here falls back to English. Translations are AI-made: native speakers, please review.
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and (AceLocale:NewLocale(ADDON, "esES") or AceLocale:NewLocale(ADDON, "esMX"))
if not L then
  return
end
L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "%d ventas y compras en la CS en los últimos 90 días. AME las registra desde el correo de subastas: abre tu buzón para capturar las nuevas."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "%d subastas activas en tus personajes, según la última vez que cada uno abrió la casa de subastas. Las ventas aparecen en el registro al instante y se liquidan cuando llega el correo de la subasta."
L["%d auctions"] = "%d subastas"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "%d clientes en los últimos 90 días, por oro gastado contigo (según el correo de subastas)."
L["%d days"] = "%d días"
L["%d days ago"] = "hace %d días"
L["%d h ago"] = "hace %d h"
L["%d h listings"] = "subastas de %d h"
L["%d items  -  showing %d-%d  -  index from %s"] = "%d objetos  -  mostrando %d-%d  -  índice de %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d objetos de %s anuncios, guardados %s ms tras la petición de escaneo"
L["%d items not searchable yet (names loading)"] = "%d objetos aún no se pueden buscar (cargando nombres)"
L["%d items summarized"] = "%d objetos resumidos"
L["%d items summarized in %s ms wall"] = "%d objetos resumidos en %s ms reales"
L["%d min ago"] = "hace %d min"
L["%d of %d known prices differ more than %dx from ours"] =
  "%d de %d precios conocidos difieren más de %dx de los nuestros"
L["%d passed, %d warnings, %d failed"] = "%d correctas, %d avisos, %d fallidas"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posiciones en %d personaje. Las bolsas se actualizan mientras juegas; abre tu banco y la casa de subastas para incluir los objetos del banco y las subastas activas."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posiciones en %d personajes. Las bolsas se actualizan mientras juegas; abre tu banco y la casa de subastas para incluir los objetos del banco y las subastas activas."
L["%d routes  -  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"] =
  "%d rutas  -  compra en %s, vende en %s: %d%% de comisión, depósitos de subastas de %dh"
L["%d scans in 7 days"] = "%d escaneos en 7 días"
L["%d scans/7d, %s"] = "%d escaneos/7d, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "%d proveedores en los últimos 90 días, por oro que gastaste con ellos (según el correo de subastas)."
L["%d watched items have no price history here yet"] = "%d objetos vigilados aún no tienen historial de precios aquí"
L["%d-day average"] = "Media de %d días"
L["%dd avg"] = "Media %dd"
L["%dx off usual"] = "%dx de lo habitual"
L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"] =
  "%s  -  creado por Tyken Evanion  -  PvP Horda, WoW Forever"
L["%s  ·  %d days of history  ·  data %s %s%s%s"] = "%s  ·  %d días de historial  ·  datos %s %s%s%s"
L["%s %s: min %s, market %s, qty %d (%d samples)"] = "%s %s: mín. %s, mercado %s, cant. %d (%d muestras)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s último (%s): mín. %s, mercado %s, %d unidades en %d subastas"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s quiere compartir precios de subasta contigo. Abre |cffffffff/ame|r > Sincronizar para aprobarlo."
L["(each point is one scan)"] = "(cada punto es un escaneo)"
L["+ %d more"] = "+ %d más"
L[", %d scans received"] = ", %d escaneos recibidos"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it"] =
  "/ame - abrir la ventana  ·  /ame <enlace de objeto> - gráfico de un objeto  ·  Alt-clic en un objeto - ver su gráfico"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - abre la ventana.   /ame <enlace de objeto> - gráfico de un objeto.   /ame status - estado de datos y sincronización.   /ame config - ajustes.   /ame selftest - comprueba que todo funciona."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <enlace> - mostrar historial  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/semana"
L["1 day"] = "1 día"
L["30 days: sold / bought"] = "30 días: vendido / comprado"
L["7-day change"] = "Cambio en 7 días"
L["7d"] = "7d"
L["7d average"] = "Media de 7 días"
L["7d avg"] = "Media 7d"
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Un filtro de todos los objetos con historial. Elige una categoría o lista de seguimiento a la izquierda, busca por nombre, filtra por calidad, rango de precios o señal, y haz clic en una columna para ordenar. Pasa el ratón sobre el encabezado de una columna para ver qué significa. Haz clic en una fila para abrir su gráfico; haz clic en la estrella para vigilarlo."
L["AH cut"] = "Comisión CS"
L["AME alert: %s %s"] = "Alerta de AME: %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "AME escucha las API propias del juego para la casa de subastas, así que se registra cada escaneo y búsqueda que hagas - desde la ventana estándar de la casa de subastas o con cualquier addon de escaneo (funciona bien con addons como Auctionator). No se escanea nada extra. El historial se guarda por mercado (reino o reglas de Forever) y casa de subastas, y los miembros de la hermandad que usan AME comparten sus escaneos completos automáticamente."
L["AceComm not available: sync disabled"] = "AceComm no disponible: sincronización desactivada"
L["Activity"] = "Actividad"
L["Add"] = "Añadir"
L["Alert when"] = "Alertar cuando"
L["Alert:"] = "Alerta:"
L["All"] = "Todo"
L["All items"] = "Todos los objetos"
L["All markets: %d, %.0f KB of compressed daily history"] =
  "Todos los mercados: %d, %.0f KB de historial diario comprimido"
L["Alliance AH"] = "CS Alianza"
L["Alliance blue"] = "Azul Alianza"
L["Always show full tooltip details (otherwise hold Shift)"] =
  "Mostrar siempre todos los detalles en la descripción emergente (si no, mantén Mayús)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Una clasificación de oportunidad de -100 a +100. Más alta significa que el objeto está más por debajo de su precio habitual, es estable y tiene tendencia alcista. Cerca de 0 significa un precio normal; negativa, más caro de lo habitual. Ordena por ella para encontrar gangas rápidamente."
L["Announce recorded full scans in chat"] = "Anunciar en el chat los escaneos completos registrados"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "Anunciado %d veces, %d escaneos servidos, %d recibidos, %d rechazados"
L["Announces your recent full scans to the guild and fetches ones you're missing, paced in the background so it never disrupts chat or raid addons. Received scans that disagree wildly with your own prices are rejected."] =
  "Anuncia tus escaneos completos recientes a la hermandad y obtiene los que te faltan, de forma pausada en segundo plano para no interferir con el chat ni con los addons de banda. Los escaneos recibidos que difieren muchísimo de tus propios precios se rechazan."
L["Any age"] = "Cualquier antigüedad"
L["Any quality"] = "Cualquier calidad"
L["Approve"] = "Aprobar"
L["Arbitrage"] = "Arbitraje"
L["Arbitrage tab"] = "Pestaña Arbitraje"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "Se ha pedido a %s que comparta. Verá una solicitud en su pestaña Sincronizar."
L["Asking prices"] = "Precios pedidos"
L["At market price"] = "A precio de mercado"
L["Auction house"] = "Casa de subastas"
L["Auction house cut"] = "Comisión de la casa de subastas"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator no está instalado: nada que importar (los escaneos se registran del juego igualmente)"
L["Auctions"] = "Subastas"
L["Average"] = "Media"
L["Average cost"] = "Coste medio"
L["Avg cost"] = "Coste med."
L["BUY"] = "COMPRAR"
L["BUY signal at %s"] = "Señal de COMPRA a %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  'COMPRAR: el precio de hoy es inusualmente bajo para este objeto - al menos 1,5 desviaciones estándar por debajo de su propia media de 30 días. VENDER: inusualmente alto según la misma medida. MANTENER: dentro de su rango normal - consérvalo si lo tienes, no hay ventaja en comprar. ESPERAR: barato, pero los vendedores están liquidando - espera a que toque fondo. Necesita 7+ días de historial ("-" hasta entonces). La fase de mercado compara el movimiento semanal del precio con la oferta: escasez, demanda estable, vendedores en masa, contracción, equilibrio, presión creciente, vendedores retirándose, demanda débil o liquidación. Compara el objeto consigo mismo, y es una pista, no un consejo financiero.'
L["Balanced"] = "Equilibrio"
L["Block"] = "Bloquear"
L["Blocked"] = "Bloqueados"
L["Buy at"] = "Comprar en"
L["By your guild officers: %s"] = "Por los oficiales de tu hermandad: %s"
L["Cancel"] = "Cancelar"
L["Candles"] = "Velas"
L["Change this if another addon (e.g. AHDB) also uses Alt-click on items."] =
  "Cambia esto si otro addon (p. ej. AHDB) también usa Alt-clic en objetos."
L["Character"] = "Personaje"
L["Character name, e.g. First Last"] = "Nombre del personaje, p. ej. Nombre Apellido"
L["Chart style"] = "Estilo de gráfico"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Comprueba cada parte de AME y ofrece recargar para guardar los resultados."
L["Checks every part of the addon, records timings, then reloads the UI."] =
  "Comprueba cada parte del addon, registra tiempos y luego recarga la IU."
L["Class %d"] = "Clase %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Haz clic en una fila para abrir su gráfico de precios. Haz clic en la estrella para añadirlo a una lista de seguimiento. Las barras tras el nombre indican cuánto fiarse de los números: 3 verdes = muchos escaneos recientes, 2 ámbar = algunos, 1 roja = pocos o antiguos."
L["Close"] = "Cerrar"
L["Commands"] = "Comandos"
L["Common+"] = "Común+"
L["Copy to my watchlists"] = "Copiar a mis listas"
L["Could not load history: %s"] = "No se pudo cargar el historial: %s"
L["Customers"] = "Clientes"
L["Data"] = "Datos"
L["Data quality"] = "Calidad de los datos"
L["Days to sell"] = "Días para vender"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "Los días en que el precio de un objeto es tantas veces superior (o inferior) al de los días vecinos se excluyen del filtro, las señales, las alertas y los gráficos - normalmente un único anuncio un 1000% más caro en un mercado poco activo. Dentro de un escaneo completo, AME ya ignora los anuncios caros: el precio de mercado usa la parte más barata de la oferta."
L["Decline"] = "Rechazar"
L["Delete list..."] = "Eliminar lista..."
L['Delete the watchlist "%s"?'] = '¿Eliminar la lista de seguimiento "%s"?'
L["Deposit"] = "Depósito"
L["Deposits for"] = "Depósitos de"
L["Depth"] = "Profundidad"
L["Disabled"] = "Desactivado"
L["Display"] = "Visualización"
L["Dumping"] = "Liquidación"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Cada vela cubre uno o más días. Abre en el cierre de la vela anterior y cierra en el precio de mercado; verde cerró más alto, roja más bajo. La mecha fina baja hasta el anuncio más barato visto."
L["Epic+"] = "Épico+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Unidades vendidas al día (estimación) donde venderías. Compáralo con cuántas piensas comprar: si se venden 5 al día, 100 tardarán semanas."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Todo lo que tienen tus personajes - bolsas, banco y subastas activas - al precio de mercado de la casa de subastas de tu facción. Los objetos del banco y las subastas cuentan según la última vez que abriste el banco / la casa de subastas."
L["Faction auction houses"] = "Casas de subastas de facción"
L["Follow market"] = "Seguir al mercado"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Para las unidades que compraste en la casa de subastas: lo que valen ahora a precio de mercado menos lo que pagaste. Se convierte en beneficio real cuando vendes."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "De tus ventas en subasta: lo que recibiste tras la comisión de la CS, menos lo que pagaste por esas unidades (primero las compras más antiguas). Las ventas de objetos obtenidos como botín o fabricados cuentan íntegras."
L["Goblin AH"] = "CS goblin"
L["Goblin auction houses"] = "Casas de subastas goblin"
L["Goblin gold"] = "Oro goblin"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Oro recibido por ventas en subasta (tras la comisión) y oro gastado en compras en subasta en los últimos 30 días."
L["Guide"] = "Guía"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Los oficiales de la hermandad pueden bloquear jugadores para todos: añade una línea "%s" a la información de la hermandad.'
L["Guild watchlists"] = "Listas de la hermandad"
L["Guild: %s"] = "Hermandad: %s"
L["HOLD"] = "MANTENER"
L["Held"] = "Tienes"
L["High"] = "Máximo"
L["History not loaded yet."] = "Historial aún no cargado."
L["Hold Shift for more AME data"] = "Mantén Mayús para más datos de AME"
L["Holdings value"] = "Valor de posiciones"
L["Horde AH"] = "CS Horda"
L["Horde red"] = "Rojo Horda"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "Lo rápido que se mueve el objeto: unidades que desaparecieron entre escaneos completos consecutivos de esta casa de subastas, por día, durante la última semana. Cuenta anuncios vendidos, cancelados y caducados, y los anuncios nuevos ocultan algunas ventas, así que tómalo como una guía aproximada. Un objeto barato que nunca se vende es una trampa; un número alto significa que puedes vender un montón rápido. Necesita varios escaneos completos el mismo día para mostrarse."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Cuánto tardarías en vender todo lo que tienes al ritmo de venta actual del objeto (estimación)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Cuántos hay anunciados en los datos más recientes. En la página del objeto, el % que aparece al lado es la tendencia semanal de la oferta: una oferta en descenso suele preceder a subidas de precio."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Cuántas unidades puedes comprar en la casa de compra antes de que la ruta deje de ser rentable, y el beneficio total: cada anuncio con precio inferior a lo que se cobra por una unidad tras la comisión. Necesita los anuncios del objeto, así que búscalo primero en la casa de compra (el botón Buscar lo hace) - después se conservan 6 horas. Vender tantas sigue llevando tiempo: mira Ventas/d."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "Cuánto se movió el precio de mercado respecto a hace 7 días de datos. Verde es subida, rojo es bajada."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "Cuánto salta el precio de un día a otro (la dispersión de los cambios diarios en % durante 30 días). Números bajos significan un objeto estable y predecible; números altos, oscilaciones arriesgadas - y mayores oportunidades."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "Qué antigüedad tiene el más viejo de los dos precios. Datos recientes en ambos lados hacen fiable una ruta - escanea ambas casas de subastas (los alters de esta cuenta cuentan) antes de comprar."
L["If Auctionator is installed: fills days that have no AME data from its recent price history."] =
  "Si Auctionator está instalado: rellena los días sin datos de AME con su historial de precios reciente."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Si Auctionator está instalado: importa sus precios diarios recientes para los días en que AME no tiene datos (CS de facción)."
L["Ignore outrageous prices"] = "Ignorar precios desorbitados"
L["Import history from Auctionator"] = "Importar historial de Auctionator"
L["Item"] = "Objeto"
L["Item name, ID, or Shift-click an item"] = "Nombre del objeto, ID o Mayús-clic en un objeto"
L["Item tab"] = "Pestaña Objeto"
L["Items"] = "Objetos"
L["Items tracked"] = "Objetos rastreados"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Objetos que puedes comprar en una casa de subastas y vender en otra con beneficio tras la comisión - p. ej. la CS de tu facción y la CS goblin (entre facciones). Cada casa de subastas tiene su propio historial, así que escanea ambas (los alters de esta cuenta cuentan). Pasa el ratón sobre las columnas para ver detalles."
L['Keep the AH open until AME says "recorded full scan".'] =
  'Mantén la CS abierta hasta que AME diga "escaneo completo registrado".'
L["Last"] = "Último"
L["Last full scan"] = "Último escaneo completo"
L["Last full scan: %d items, %s"] = "Último escaneo completo: %d objetos, %s"
L["Last received: %d items from %s, %s"] = "Último recibido: %d objetos de %s, %s"
L["Last rejected:"] = "Último rechazado:"
L["Ledger"] = "Registro"
L["Left-click: window   Right-click: settings"] = "Clic izquierdo: ventana   Clic derecho: ajustes"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 no cargado"
L["LibDeflate not loaded"] = "LibDeflate no cargado"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "Anunciados en la casa de compra / en la casa de venta. Mucho para comprar y poca competencia donde vendes es lo ideal; una gran diferencia por un solo anuncio en la casa de compra puede desaparecer rápido."
L["Listed on the AH now"] = "En la CS ahora"
L["Listed on the auction house now"] = "En la casa de subastas ahora"
L["Loading history..."] = "Cargando historial..."
L["Loading market data..."] = "Cargando datos de mercado..."
L["Loading recent scans..."] = "Cargando escaneos recientes..."
L["Low (cheapest)"] = "Mínimo (más barato)"
L["Lowest"] = "Mínimo"
L["Margin"] = "Margen"
L["Market"] = "Mercado"
L["Market price"] = "Precio de mercado"
L["Market tab"] = "Pestaña Mercado"
L["Market: %s"] = "Mercado: %s"
L["Modified click on items in bags, chat links and the auction house. Choose Alt+Shift if another addon (e.g. AHDB) already uses Alt-click."] =
  "Clic con modificador en objetos de las bolsas, enlaces del chat y la casa de subastas. Elige Alt+Mayús si otro addon (p. ej. AHDB) ya usa Alt-clic."
L["Mostly"] = "Sobre todo"
L["Name for the new watchlist:"] = "Nombre de la nueva lista:"
L["New list"] = "Nueva lista"
L["New list..."] = "Nueva lista..."
L["No full scan recorded yet."] = "Aún no se ha registrado ningún escaneo completo."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Aún no hay historial para este objeto. Búscalo en la casa de subastas o haz un escaneo completo."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Aún no hay datos de mercado de la casa de subastas de tu facción - escanea allí para valorar tus posiciones."
L["No one yet."] = "Nadie todavía."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Aún no hay historial de precios de la %s: escanea allí (sirve cualquier personaje de esta cuenta) para comparar."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Aún no hay historial de precios de la %s: escanea allí (sirve cualquier personaje de esta cuenta)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "No hay escaneos de este objeto en los últimos 2 días. El historial diario está en los otros rangos."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Nadie todavía. Añade a un amigo arriba - también necesita AME y debe aprobarlo."
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Aún no se ha recibido nada - los escaneos llegan cuando alguien con quien compartes hace un escaneo completo."
L["Notifications"] = "Notificaciones"
L["Off"] = "Desactivado"
L["Open"] = "Apertura"
L["Open an item's chart with"] = "Abrir el gráfico de un objeto con"
L["Open item charts with"] = "Abrir gráficos de objetos con"
L["Open the window with %s."] = "Abre la ventana con %s."
L["Pick two different auction houses."] = "Elige dos casas de subastas distintas."
L["Play a sound when a watchlist alert fires"] = "Reproducir un sonido cuando salte una alerta de una lista"
L["Player"] = "Jugador"
L["Portfolio"] = "Cartera"
L["Portfolio tab"] = "Pestaña Cartera"
L["Positions"] = "Posiciones"
L["Pressure building"] = "Presión creciente"
L["Price"] = "Precio"
L["Price each"] = "Precio unitario"
L["Profit"] = "Beneficio"
L["Qty"] = "Cant."
L["Rare+"] = "Raro+"
L["Reading the numbers"] = "Cómo leer los números"
L["Realized profit"] = "Beneficio realizado"
L["Realized profit, 7 days"] = "Beneficio realizado, 7 días"
L["Rebuild market index"] = "Reconstruir índice de mercado"
L["Recently heard from"] = "Contactos recientes"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Recalcula los resúmenes de 30 días que usan el filtro, las descripciones emergentes y las alertas."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Registra los precios de la casa de subastas de cada escaneo y búsqueda que hagas (API nativas; funciona con cualquier addon de escaneo), por reino y casa de subastas."
L["Reload UI"] = "Recargar IU"
L["Requests"] = "Solicitudes"
L["Reset"] = "Restablecer"
L["Run self-test"] = "Ejecutar autoprueba"
L["SELL"] = "VENDER"
L["SELL signal at %s"] = "Señal de VENTA a %s"
L["Score"] = "Puntuación"
L["Search"] = "Buscar"
L["Search items..."] = "Buscar objetos..."
L["Seen in 3 days"] = "Visto en 3 días"
L["Seen in 7 days"] = "Visto en 7 días"
L["Seen today/yesterday"] = "Visto hoy/ayer"
L["Sell at"] = "Vender en"
L["Sellers piling in"] = "Vendedores en masa"
L["Sellers withdrawing"] = "Vendedores retirándose"
L["Sells for"] = "Se vende por"
L["Sells per day (estimate)"] = "Ventas al día (estimación)"
L["Sells per day at the sell house"] = "Ventas al día en la casa de venta"
L["Sells/d"] = "Ventas/d"
L["Settings"] = "Ajustes"
L["Share full scans with guild members who use AME"] =
  "Compartir escaneos completos con miembros de la hermandad que usen AME"
L["Share full scans with my guild (members running AME)"] =
  "Compartir escaneos completos con mi hermandad (miembros con AME)"
L["Share with guild"] = "Compartir con la hermandad"
L["Share with trusted players (below)"] = "Compartir con jugadores de confianza (abajo)"
L["Sharing"] = "Compartir"
L["Sharing settings are on the Sync tab. These options are also in the game's AddOns settings."] =
  "Los ajustes para compartir están en la pestaña Sincronizar. Estas opciones también están en los ajustes de AddOns del juego."
L["Shift-click to search the auction house"] = "Mayús-clic para buscar en la casa de subastas"
L["Shortage"] = "Escasez"
L["Show AME prices in item tooltips"] = "Mostrar precios de AME en las descripciones de objetos"
L["Show market data in item tooltips"] = "Mostrar datos de mercado en las descripciones de objetos"
L["Show minimap button"] = "Mostrar botón del minimapa"
L["Signal"] = "Señal"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Las señales y la puntuación comparan un objeto con su propio historial, así que necesitan una semana o más de datos para significar algo. Los objetos baratos Y estables (baja volatilidad) puntúan más alto. Que la oferta baje mientras el precio se mantiene suele ser una buena señal temprana. Nada de esto es un consejo - los mercados pueden comportarse de forma extraña durante un tiempo."
L["Sold / bought"] = "Vendido / comprado"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  'Marca objetos con la estrella para ponerlos en una lista de seguimiento; crea más listas con "+ Nueva lista" en la barra lateral (clic derecho en una lista para compartirla con tu hermandad o eliminarla; las listas compartidas por miembros de la hermandad aparecen debajo de las tuyas). En la página de un objeto, configura una alerta: por debajo o por encima de un precio en oro, o cuando aparezca una señal de compra/venta. Las alertas se comprueban tras cada escaneo y se publican en el chat con un sonido.'
L["Steady demand"] = "Demanda estable"
L["Suppliers"] = "Proveedores"
L["Supply"] = "Oferta"
L["Swap"] = "Intercambiar"
L["Sync"] = "Sincronizar"
L["Sync is unavailable: the AceComm library didn't load."] =
  "La sincronización no está disponible: la biblioteca AceComm no se cargó."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "El precio de mercado diario medio durante el periodo elegido (Ajustes > Periodo de la media, 7 días por defecto). Compáralo con el precio de mercado de hoy para ver si el objeto está barato o caro ahora mismo."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "El anuncio más barato en la casa de subastas donde compras - lo que te cuestan las primeras unidades."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "El precio de mercado en la casa de subastas donde vendes: por lo que suele venderse el objeto allí."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Alt-click any item in the game (bags, chat, the AH) to open it here."] =
  "El gráfico de precios: precio de mercado, anuncio más barato, media de 7 días y oferta. Cambia a velas para una vista de trading. La rueda del ratón hace zoom, arrastrar desplaza, doble clic restablece. Alt-clic en cualquier objeto del juego (bolsas, chat, la CS) para abrirlo aquí."
L["The selling auction house's cut of the sale: 5% at faction auction houses and 15% at the goblin ones (WoW Forever's rates; adjustable in Settings). The deposit isn't subtracted - you get it back when the item sells."] =
  "La comisión de la casa de subastas de venta: 5% en las casas de subastas de facción y 15% en las goblin (tarifas de WoW Forever; ajustable en Ajustes). El depósito no se resta - lo recuperas cuando se vende el objeto."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Este mercado: %d días de historial, %d escaneos recientes guardados completos"
L["Tightening"] = "Contracción"
L["Time left"] = "Tiempo restante"
L["Top buy signals"] = "Mejores señales de compra"
L["Total"] = "Total"
L["Trusted"] = "De confianza"
L["Trusted (%d)"] = "De confianza (%d)"
L["Trusted players"] = "Jugadores de confianza"
L["Type %d"] = "Tipo %d"
L["Unblock"] = "Desbloquear"
L["Uncommon+"] = "Poco común+"
L["Unrealized"] = "No realizado"
L["Unrealized profit"] = "Beneficio no realizado"
L["Value"] = "Valor"
L["Volatility"] = "Volatilidad"
L["WAIT"] = "ESPERAR"
L["Watch"] = "Vigilar"
L["Watchlists and alerts"] = "Listas de seguimiento y alertas"
L["Weak demand"] = "Demanda débil"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "Lo que tienen todos tus personajes, valorado al mercado de tu facción, con el coste y el beneficio no realizado de lo que compraste en la CS, la señal Comprar/Mantener/Vender y cuánto tardaría en venderse. El registro muestra tus ventas y compras en la CS - registradas desde el correo de subastas cuando abres tu buzón."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Lo que cuesta de entrada anunciar uno en la casa de venta: una parte del precio de venta al vendedor del objeto (CS de facción 5/20/60% para 2/8/24 horas, CS goblin cinco veces eso), como mínimo 1 de plata. Lo recuperas cuando se vende y lo pierdes si no - así que un depósito alto en algo que se vende lento es un riesgo real."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "Por lo que suele venderse el objeto ahora mismo. Con datos completos de anuncios es la media del 15-30% más barato de la oferta en la casa de subastas, lo que ignora algunos anuncios baratos o absurdos. Con un resumen de navegación (lo que muchos escáneres hacen por defecto) solo se conoce el anuncio más barato, así que entonces es el precio más bajo."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Lo que pagaste por unidad por las unidades que compraste en la casa de subastas (las compras más antiguas se venden primero). Los objetos obtenidos como botín o fabricados no tienen coste."
L["When"] = "Cuándo"
L["Where the data comes from"] = "De dónde vienen los datos"
L["Window colours"] = "Colores de la ventana"
L["You haven't blocked anyone."] = "No has bloqueado a nadie."
L["You'd receive (after the cut)"] = "Recibirías (tras la comisión)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Tus subastas activas en todos los personajes, según la última vez que cada uno abrió la casa de subastas."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "Tus alters de esta cuenta de Battle.net ya lo comparten todo: el historial de AME se guarda para toda la cuenta. Confía en jugadores para intercambiar escaneos con amigos o con tus propios personajes de otras cuentas. Solo se comparten tu mercado y tu casa de subastas, y los escaneos que difieren muchísimo de tus precios se rechazan."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "Tu correo de subastas no nombra al otro jugador en este cliente (la casa de subastas lo mantiene anónimo), así que no hay nadie que mostrar."
L["a list needs a name"] = "la lista necesita un nombre"
L["a list with that name already exists"] = "ya existe una lista con ese nombre"
L["above g"] = "más de g"
L["announced %d, served %d, received %d, rejected %d"] = "anunciados %d, servidos %d, recibidos %d, rechazados %d"
L["auctionator history import"] = "importación de historial de Auctionator"
L["average period"] = "periodo de la media"
L["awaiting mail"] = "esperando correo"
L["backfill"] = "relleno de historial"
L["below g"] = "menos de g"
L["blocked"] = "bloqueado"
L["blocked %s"] = "%s bloqueado"
L["bought"] = "comprado"
L["chart library + window"] = "biblioteca de gráficos + ventana"
L["codec+compress 6.4k items"] = "códec+compresión 6.4k objetos"
L["could not load %s: %s"] = "no se pudo cargar %s: %s"
L["could not load history addon"] = "no se pudo cargar el addon de historial"
L["couldn't start an auction house search for %s"] = "no se pudo iniciar una búsqueda en la casa de subastas para %s"
L["data"] = "datos"
L["done %s"] = "hecho %s"
L["down  (wick = cheapest)"] = "baja  (mecha = más barato)"
L["dropped to %s (alert at %s)"] = "bajó a %s (alerta en %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "codificar %.0f ms, comprimir %.0f ms, desempaquetar+decodificar %.0f ms, %d KB -> %d KB"
L["ended?"] = "¿terminada?"
L["enter a character name"] = "introduce un nombre de personaje"
L["guild sync"] = "sincronización de hermandad"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "sincronización de hermandad: %s, anunciados %d, servidos %d, recibidos %d, rechazados %d"
L["history addon"] = "addon de historial"
L["history import from Auctionator failed: %s"] = "falló la importación de historial de Auctionator: %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "la importación de historial de Auctionator solo se hace en la casa de subastas de tu facción (sus datos mezclan todas las casas)."
L["history import from Auctionator skipped: %s"] = "importación de historial de Auctionator omitida: %s"
L["history lookup (cold)"] = "consulta de historial (en frío)"
L["history: %d raw scans, %d days, %.0f KB"] = "historial: %d escaneos en bruto, %d días, %.0f KB"
L["imported %d days of price history from Auctionator into %s"] =
  "importados %d días de historial de precios de Auctionator a %s"
L["item %d: %d points in %.1f ms"] = "objeto %d: %d puntos en %.1f ms"
L["item from latest scan has no daily points"] = "el objeto del último escaneo no tiene puntos diarios"
L["item not loaded yet - try again in a moment"] = "objeto aún no cargado - inténtalo de nuevo en un momento"
L["just now"] = "justo ahora"
L["last full scan"] = "último escaneo completo"
L["last full scan: %d items, %s ago"] = "último escaneo completo: %d objetos, hace %s"
L["last seen %s"] = "visto por última vez %s"
L["libraries"] = "bibliotecas"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] =
  "cargado en %s ms, %d fragmento(s), %.0f KB de historial diario"
L["loading history..."] = "cargando historial..."
L["loading item names %d/%d"] = "cargando nombres de objetos %d/%d"
L["low"] = "bajo"
L["lowest"] = "mínimo"
L["margin %"] = "margen %"
L["market"] = "mercado"
L["market index"] = "índice de mercado"
L["market index failed:"] = "falló el índice de mercado:"
L["max g"] = "máx. g"
L["min g"] = "mín. g"
L["never"] = "nunca"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "aún no hay escaneo completo registrado: abre la CS y haz un escaneo completo (el de tu addon de escaneo o el del juego)"
L["no history for %s in %s"] = "no hay historial para %s en %s"
L["no scans in this shard yet"] = "aún no hay escaneos en este fragmento"
L["none"] = "ninguno"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "ninguno aún: abre la CS y haz un escaneo completo, luego vuelve a ejecutar /ame selftest"
L["not in a guild"] = "no estás en una hermandad"
L["not loaded"] = "no cargado"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "nada importado aquí (solo con datos de Auctionator, en la casa de subastas de tu facción)"
L["off"] = "desactivado"
L["on"] = "activado"
L["on buy/sell signal"] = "con señal de compra/venta"
L["on, but you're not in a guild"] = "activado, pero no estás en una hermandad"
L["open the auction house first"] = "abre primero la casa de subastas"
L["profit g"] = "beneficio g"
L["reading full scan (%d listings) in the background..."] = "leyendo escaneo completo (%d anuncios) en segundo plano..."
L["received a full scan from %s via sync (%d items, %s)"] =
  "recibido un escaneo completo de %s por sincronización (%d objetos, %s)"
L["recorded full scan: %d items from %d listings (%s)"] = "escaneo completo registrado: %d objetos de %d anuncios (%s)"
L["rose to %s (alert at %s)"] = "subió a %s (alerta en %s)"
L["round trip mismatch"] = "discrepancia en ida y vuelta"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "flujo de escaneo: %d peticiones, %d eventos (%d desde la última petición), leído %s, abortados %d; ingesta requested=%s reading=%s"
L["scan read failed:"] = "falló la lectura del escaneo:"
L["score"] = "puntuación"
L["score %+d"] = "puntuación %+d"
L["search"] = "buscar"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "autoprueba terminada:\n%s\n\n¿Recargar la IU ahora para guardar los resultados?"
L["selftest starting (this may pause the game for a moment)"] =
  "iniciando autoprueba (puede pausar el juego un momento)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "autoprueba: %d correctas, %d avisos, %d fallidas. Recarga para guardar los resultados (/reload)."
L["shard"] = "fragmento"
L["shared"] = "compartida"
L["sharing"] = "compartir"
L["signal"] = "señal"
L["sold"] = "vendido"
L["storing %s scan failed:"] = "falló al guardar el escaneo %s:"
L["supply"] = "oferta"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "la CS se cerró antes de que AME terminara de leer el escaneo completo; no se registró."
L["today"] = "hoy"
L["turned off in settings"] = "desactivado en los ajustes"
L["unknown command, try /ame help"] = "comando desconocido, prueba /ame help"
L["up"] = "sube"
L["usage: /ame item <item link or itemID>"] = "uso: /ame item <enlace de objeto o itemID>"
L["volatility"] = "volatilidad"
L["waiting for them to approve"] = "esperando su aprobación"
L["wants to share, %s"] = "quiere compartir, %s"
L["wheel: zoom, drag: pan, double-click: reset"] = "rueda: zoom, arrastrar: desplazar, doble clic: restablecer"
L["whisper"] = "susurro"
L["window created, market tab rendered"] = "ventana creada, pestaña de mercado dibujada"
L["yesterday"] = "ayer"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "estás en la CS de compra: Buscar (o Mayús-clic en una fila) para comprar"
L["%d ahead"] = "%d delante"
L["<1h"] = "<1 h"
L["Normal %s"] = "Normal %s"
L["Patient %s"] = "Paciente %s"
L["Post at"] = "Subastar a"
L["Posting price"] = "Precio de subasta"
L["Posting price: not enough data on this item yet."] =
  "Precio de subasta: aún no hay datos suficientes de este objeto."
L["Quick %s"] = "Rápido %s"
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "A qué precio subastar para que se venda dentro de la duración de la subasta, en lugar de rebajar en 1 cobre la subasta más barata. Los compradores se llevan primero las subastas más baratas, así que AME cuenta las unidades que tienes delante en cada precio, lo rápido que se vende el objeto y con qué frecuencia nuevas subastas te rebajan, y sopesa la probabilidad de vender frente al depósito que pierdes si no se vende. Rápido vende casi seguro en pocas horas, Normal es el mejor precio para esa probabilidad, Paciente es el precio más alto que aún vende aproximadamente la mitad de las veces. AME aprende el patrón de cada objeto a partir de tus escaneos (horas punta, días de la semana, cuánto compiten los vendedores) y de tus propias subastas: si los objetos caducan a menudo a sus precios, se vuelve más prudente con ese objeto. Con pocos datos se basa en objetos similares; las barras muestran cuánto sabe."
L["a week+"] = "una semana+"
L["deposit %s"] = "depósito %s"
L["unlikely to sell soon: consider holding"] = "difícil que se venda pronto: considera mantener"
L["well below its usual price"] = "muy por debajo de su precio habitual"
L["~%d days"] = "~%d días"
L["~%dh"] = "~%d h"
