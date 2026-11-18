-- Russian. Keys are the English texts (Locales/enUS.lua);
-- anything not translated here falls back to English.
-- Translations are AI-made: native speakers, please review (CurseForge's translation tool, or a pull request).
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:NewLocale(ADDON, "ruRU")
if not L then
  return
end

L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "Продаж и покупок на аукционе за последние 90 дней: %d. AME записывает их по почте аукциона: откройте почтовый ящик, чтобы учесть новые."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "Активных аукционов на ваших персонажах: %d (на момент, когда каждый из них последний раз открывал аукцион). Продажи сразу появляются в журнале и закрываются, когда приходит письмо с аукциона."
L["%d ahead"] = "%d впереди"
L["%d auctions"] = "Аукционов: %d"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "Покупателей за последние 90 дней: %d, по золоту, потраченному у вас (по почте аукциона)."
L["%d days"] = "%d дн."
L["%d days ago"] = "%d дн. назад"
L["%d h ago"] = "%d ч назад"
L["%d h listings"] = "лоты на %d ч"
L["%d items"] = "%d предметов"
L["%d items  ·  showing %d-%d  ·  index from %s"] =
  "Предметов: %d  ·  показаны %d-%d  ·  индекс от %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d предметов из %s лотов, сохранено через %s мс после запроса сканирования"
L["%d items not searchable yet (names loading)"] =
  "%d предметов пока нельзя найти (загружаются названия)"
L["%d items summarized"] = "Обобщено предметов: %d"
L["%d items summarized in %s ms wall"] =
  "Обобщено предметов: %d за %s мс реального времени"
L["%d min ago"] = "%d мин назад"
L["%d of %d known prices differ more than %dx from ours"] =
  "%d из %d известных цен отличаются от наших более чем в %d раз"
L["%d outlier price ignored"] = "%d выброс цены проигнорирован"
L["%d outlier prices ignored"] = "проигнорировано выбросов цены: %d"
L["%d passed, %d warnings, %d failed"] = "Пройдено: %d, предупреждений: %d, ошибок: %d"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "Позиций: %d на персонажах: %d. Сумки обновляются по ходу игры; откройте банк и аукцион, чтобы учесть предметы в банке и активные аукционы."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "Позиций: %d на персонажах: %d. Сумки обновляются по ходу игры; откройте банк и аукцион, чтобы учесть предметы в банке и активные аукционы."
L["%d routes  ·  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"] =
  "Маршрутов: %d  ·  покупка: %s, продажа: %s: комиссия %d%%, залог за лоты на %d ч"
L["%d scans in 7 days"] = "%d сканирований за 7 дней"
L["%d scans/7d, %s"] = "%d скан./7д, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "Поставщиков за последние 90 дней: %d, по золоту, которое вы у них потратили (по почте аукциона)."
L["%d watched items have no price history here yet"] =
  "У %d отслеживаемых предметов здесь пока нет истории цен"
L["%d-day average"] = "Среднее за %d дн."
L["%dd avg"] = "Ср. %dд"
L["%dx off usual"] = "В %d раз от обычного"
L["%s  ·  %d days of history  ·  data %s %s%s%s"] = "%s  ·  %d дн. истории  ·  данные %s %s%s%s"
L["%s %s: min %s, market %s, qty %d (%d samples)"] =
  "%s %s: мин. %s, рынок %s, кол-во %d (%d замеров)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s последнее (%s): мин. %s, рынок %s, %d шт. в %d лотах"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s хочет делиться с вами ценами аукциона. Откройте |cffffffff/ame|r > Синхронизация, чтобы одобрить."
L["(each point is one scan)"] = "(каждая точка - одно сканирование)"
L["(est.)"] = "(оценка)"
L["(needs LibDBIcon; included in releases)"] = "(нужен LibDBIcon; входит в релизы)"
L["+ %d more"] = "+ ещё %d"
L[", %d scans received"] = ", получено сканирований: %d"
L["...and close it when the auction house closes"] = "...и закрывать при закрытии аукциона"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Shift-click an item with the window open - chart it"] =
  "/ame - открыть окно  ·  /ame <ссылка на предмет> - график предмета  ·  Shift-клик по предмету при открытом окне - его график"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - открыть окно.   /ame <ссылка на предмет> - график предмета.   /ame status - состояние данных и синхронизации.   /ame config - настройки.   /ame selftest - проверить, что всё работает."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <ссылка> - вывести историю  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/нед."
L["1 day"] = "1 день"
L["30 days: sold / bought"] = "30 дней: продано / куплено"
L["7-day change"] = "Изменение за 7 дней"
L["7d"] = "7д"
L["7d average"] = "Среднее за 7 дней"
L["7d avg"] = "Ср. 7д"
L["7d change"] = "Изм. 7д"
L["<1h"] = "<1 ч"
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Скринер всех предметов с историей. Выберите категорию или список наблюдения слева, ищите по названию, фильтруйте по качеству, диапазону цен или сигналу и щёлкните по столбцу для сортировки. Наведите курсор на заголовок столбца, чтобы узнать его смысл. Щёлкните по строке, чтобы открыть график; щёлкните по звезде, чтобы отслеживать предмет."
L["AH cut"] = "Комиссия аук."
L["AME alert: %s %s"] = "Оповещение AME: %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "AME слушает собственные API аукциона в игре, поэтому записывается каждое ваше сканирование и поиск - из стандартного окна аукциона или любого аддона-сканера (хорошо работает с аддонами вроде Auctionator). Ничего лишнего не сканируется. История хранится отдельно для каждого рынка (игровой мир или правила Forever) и аукциона, а члены гильдии с AME автоматически делятся полными сканированиями."
L["API + database found"] = "API и база данных найдены"
L["API found, database not readable (no backfill)"] =
  "API найден, база данных не читается (без дозаполнения истории)"
L["Accept"] = "Принять"
L["AceComm not available: sync disabled"] =
  "AceComm недоступен: синхронизация отключена"
L["Activity"] = "Активность"
L["Add"] = "Добавить"
L["Add to a watchlist"] = "Добавить в список наблюдения"
L["Alert when"] = "Оповещать, когда"
L["Alert:"] = "Оповещение:"
L["All"] = "Все"
L["All items"] = "Все предметы"
L["All markets: %d, %.0f KB of compressed daily history"] =
  "Все рынки: %d, %.0f КБ сжатой дневной истории"
L["All of AME's settings are in its own window: %s, Settings tab."] =
  "Все настройки AME находятся в его собственном окне: %s, вкладка «Настройки»."
L["Alliance AH"] = "Аукцион Альянса"
L["Alliance blue"] = "Синий Альянса"
L["Alt+Shift-click"] = "Alt+Shift-клик"
L["Alt-click"] = "Alt-клик"
L["Always show full tooltip details (otherwise hold Shift)"] =
  "Всегда показывать все данные в подсказке (иначе удерживайте Shift)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Рейтинг возможности от -100 до +100. Чем выше, тем сильнее предмет ниже своей обычной цены, при этом он стабилен и растёт. Около 0 - обычная цена; отрицательное значение - дороже обычного. Сортируйте по нему, чтобы быстро находить выгодные покупки."
L["Announce recorded full scans in chat"] =
  "Объявлять в чате о записанных полных сканированиях"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "Объявлено раз: %d, отдано сканирований: %d, получено: %d, отклонено: %d"
L["Any age"] = "Любой давности"
L["Any quality"] = "Любое качество"
L["Approve"] = "Одобрить"
L["Arbitrage"] = "Арбитраж"
L["Arbitrage tab"] = "Вкладка «Арбитраж»"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "Запрос отправлен игроку %s. Он увидит его на своей вкладке «Синхронизация»."
L["Asking prices"] = "Цены предложения"
L["At market price"] = "По рыночной цене"
L["Auction house"] = "Аукцион"
L["Auction house cut"] = "Комиссия аукциона"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator не установлен: импортировать нечего (сканирования всё равно записываются из игры)"
L["Auctions"] = "Аукционы"
L["Average"] = "Среднее"
L["Average cost"] = "Средняя цена покупки"
L["Avg cost"] = "Ср. цена пок."
L["Azeroth Mercantile Exchange %s  ·  created by Tyken Evanion  ·  PvP Horde, WoW Forever"] =
  "Azeroth Mercantile Exchange %s  ·  автор Tyken Evanion  ·  PvP Орда, WoW Forever"
L["BUY"] = "КУПИТЬ"
L["BUY signal at %s"] = "Сигнал КУПИТЬ по %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  'КУПИТЬ: сегодняшняя цена необычно низкая для этого предмета - минимум на 1,5 стандартного отклонения ниже его собственного 30-дневного среднего. ПРОДАТЬ: необычно высокая по той же мерке. ДЕРЖАТЬ: в обычном диапазоне - держите, если есть, покупать смысла нет. ЖДАТЬ: дёшево, но продавцы сбрасывают - дождитесь дна. Нужно 7+ дней истории (до тех пор "-"). Фаза рынка сопоставляет недельное движение цены с предложением: дефицит, устойчивый спрос, наплыв продавцов, сжатие предложения, равновесие, нарастающее давление, уход продавцов, слабый спрос или сброс. Предмет сравнивается сам с собой, и это подсказка, а не финансовый совет.'
L["Balanced"] = "Равновесие"
L["Block"] = "Блокировать"
L["Blocked"] = "Заблокированы"
L["Building market index..."] = "Построение рыночного индекса..."
L["Buy"] = "Купить"
L["Buy at"] = "Купить в"
L["By your guild officers: %s"] = "Офицерами вашей гильдии: %s"
L["Cancel"] = "Отмена"
L["Candles"] = "Свечи"
L["Character"] = "Персонаж"
L["Character name, e.g. First Last"] = "Имя персонажа, например Имя Фамилия"
L["Chart style"] = "Вид графика"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Проверяет все части AME и предлагает перезагрузку, чтобы сохранить результаты."
L["Class %d"] = "Класс %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Щёлкните по строке, чтобы открыть график цен. Щёлкните по звезде, чтобы добавить предмет в список наблюдения. Полоски после названия показывают, насколько можно доверять числам: 3 зелёные = много свежих сканирований, 2 жёлтые = немного, 1 красная = мало или устаревшие."
L["Close"] = "Закрыть"
L["Commands"] = "Команды"
L["Common+"] = "Обычное+"
L["Copy to my watchlists"] = "Копировать в мои списки"
L["Could not load history: %s"] = "Не удалось загрузить историю: %s"
L["Ctrl+Alt-click"] = "Ctrl+Alt-клик"
L["Customers"] = "Покупатели"
L["Data"] = "Данные"
L["Data quality"] = "Качество данных"
L["Days to sell"] = "Дней на продажу"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "Дни, когда цена предмета во столько раз выше (или ниже) соседних дней, исключаются из скринера, сигналов, оповещений и графиков - обычно это один лот с наценкой 1000% на вялом рынке. В полном сканировании AME и так игнорирует дорогие лоты: рыночная цена берётся из самой дешёвой части предложения."
L["Decline"] = "Отклонить"
L["Delete"] = "Удалить"
L["Delete list..."] = "Удалить список..."
L['Delete the watchlist "%s"?'] = 'Удалить список наблюдения "%s"?'
L["Deposit"] = "Залог"
L["Deposits for"] = "Залог за"
L["Depth"] = "Глубина"
L["Display"] = "Отображение"
L["Dock AME beside the auction house when there's room"] =
  "Пристыковывать AME рядом с аукционом, если есть место"
L["Dumping"] = "Сброс"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Каждая свеча охватывает один или несколько дней. Она открывается по закрытию предыдущей свечи и закрывается по рыночной цене; зелёная закрылась выше, красная ниже. Тонкая тень доходит до самого дешёвого замеченного лота."
L["Epic+"] = "Эпическое+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Оценка проданных за день штук там, где вы продаёте. Сравните с тем, сколько планируете купить: если продаётся 5 в день, 100 уйдут за недели."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Всё, что есть у ваших персонажей - сумки, банк и активные аукционы - по рыночной цене аукциона вашей фракции. Предметы в банке и аукционы учитываются на момент, когда вы последний раз открывали банк / аукцион."
L["Faction auction houses"] = "Аукционы фракций"
L["Follow market"] = "Следовать рынку"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Для штук, купленных на аукционе: сколько они стоят сейчас по рыночной цене минус то, что вы заплатили. Становится реальной прибылью при продаже."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "С ваших продаж на аукционе: полученное после комиссии аукциона минус то, что вы заплатили за эти штуки (сначала самые старые покупки). Продажи добытых или созданных предметов учитываются полностью."
L["Goblin AH"] = "Аукцион гоблинов"
L["Goblin auction houses"] = "Аукционы гоблинов"
L["Goblin gold"] = "Золото гоблинов"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Золото, полученное с продаж на аукционе (после комиссии), и золото, потраченное на покупки на аукционе, за последние 30 дней."
L["Guide"] = "Справка"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Офицеры гильдии могут блокировать игроков для всех: добавьте строку "%s" в информацию о гильдии.'
L["Guild watchlists"] = "Списки гильдии"
L["Guild: %s"] = "Гильдия: %s"
L["HOLD"] = "ДЕРЖАТЬ"
L["Held"] = "На руках"
L["High"] = "Максимум"
L["History not loaded yet."] = "История ещё не загружена."
L["Hold"] = "Держать"
L["Hold Shift for more AME data"] = "Удерживайте Shift для доп. данных AME"
L["Holdings value"] = "Стоимость позиций"
L["Horde AH"] = "Аукцион Орды"
L["Horde red"] = "Красный Орды"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "Как быстро продаётся предмет: штуки, исчезнувшие между последовательными полными сканированиями этого аукциона, в день, за последнюю неделю. Учитываются проданные, отменённые и истёкшие лоты, а новые лоты скрывают часть продаж, так что это лишь грубый ориентир. Дешёвый предмет, который никогда не продаётся, - ловушка; большое число значит, что стопку можно продать быстро. Для показа нужно несколько полных сканирований в один день."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Сколько времени займёт продажа всего, что у вас есть, при текущем темпе продаж предмета (оценка)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Сколько выставлено в последних данных. На странице предмета % рядом - недельный тренд предложения: падение предложения часто предшествует росту цен."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Сколько штук можно купить на аукционе покупки, пока маршрут не перестанет окупаться, и общая прибыль: каждый лот дешевле, чем выручка за штуку после комиссии. Нужны лоты предмета, поэтому сначала найдите его на аукционе покупки (это делает кнопка «Поиск») - затем они хранятся 6 часов. Продать столько всё равно требует времени: смотрите Прод./д."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "Насколько рыночная цена изменилась по сравнению с данными 7-дневной давности. Зелёный - рост, красный - падение."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "Насколько цена прыгает изо дня в день (разброс дневных изменений в % за 30 дней). Низкие числа - стабильный, предсказуемый предмет; высокие - рискованные колебания и большие возможности."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "Возраст более старой из двух цен. Свежие данные с обеих сторон делают маршрут надёжным - отсканируйте оба аукциона (твинки на этой учётной записи тоже считаются) перед покупкой."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Если установлен Auctionator: импортирует его недавние дневные цены за дни, по которым у AME нет данных (аукцион фракции)."
L["Ignore outrageous prices"] = "Игнорировать несуразные цены"
L["Import history from Auctionator"] = "Импорт истории из Auctionator"
L["Item"] = "Предмет"
L["Item name, ID, or Shift-click an item"] =
  "Название предмета, ID или Shift-клик по предмету"
L["Item tab"] = "Вкладка «Предмет»"
L["Items"] = "Предметы"
L["Items tracked"] = "Отслеживается предметов"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Предметы, которые можно купить на одном аукционе и продать на другом с прибылью после комиссии - например, аукцион вашей фракции и аукцион гоблинов (межфракционный). У каждого аукциона своя история, так что сканируйте оба (твинки на этой учётной записи тоже считаются). Наведите курсор на столбцы для подробностей."
L['Keep the AH open until AME says "recorded full scan".'] =
  'Не закрывайте аукцион, пока AME не напишет "полное сканирование записано".'
L["Last"] = "Последняя"
L["Last full scan"] = "Последнее полное сканирование"
L["Last full scan: %d items, %s"] =
  "Последнее полное сканирование: %d предметов, %s"
L["Last received: %d items from %s, %s"] = "Последнее полученное: %d предметов от %s, %s"
L["Last rejected:"] = "Последнее отклонённое:"
L["Ledger"] = "Журнал"
L["Left-click: window   Right-click: settings"] = "ЛКМ: окно   ПКМ: настройки"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 не загружена"
L["LibDeflate not loaded"] = "LibDeflate не загружена"
L["Line"] = "Линия"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "Выставлено на аукционе покупки / на аукционе продажи. Идеально, когда купить можно много, а конкурентов там, где продаёте, мало; большой разрыв из-за одного лота на аукционе покупки может быстро исчезнуть."
L["Listed on the AH now"] = "Сейчас на аукционе"
L["Listed on the auction house now"] = "Сейчас выставлено на аукционе"
L["Loading history..."] = "Загрузка истории..."
L["Loading market data..."] = "Загрузка рыночных данных..."
L["Loading recent scans..."] = "Загрузка недавних сканирований..."
L["Low (cheapest)"] = "Минимум (самый дешёвый)"
L["Lowest"] = "Минимум"
L["Margin"] = "Маржа"
L["Market"] = "Рынок"
L["Market price"] = "Рыночная цена"
L["Market tab"] = "Вкладка «Рынок»"
L["Market: %s"] = "Рынок: %s"
L["Mostly"] = "Чаще всего"
L["Name for the new watchlist:"] = "Название нового списка:"
L["New list"] = "Новый список"
L["New list..."] = "Новый список..."
L["No full scan recorded yet."] = "Полное сканирование ещё не записано."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Для этого предмета ещё нет истории. Найдите его на аукционе или выполните полное сканирование."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Рыночных данных по аукциону вашей фракции пока нет - отсканируйте его, чтобы оценить позиции."
L["No one yet."] = "Пока никого."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Истории цен (%s) пока нет: отсканируйте там (подойдёт любой персонаж этой учётной записи), чтобы сравнить."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Истории цен (%s) пока нет: отсканируйте там (подойдёт любой персонаж этой учётной записи)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "За последние 2 дня этот предмет не сканировался. Дневная история - на других интервалах."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Пока никого. Добавьте друга выше - у него тоже должен быть AME, и он должен одобрить."
L["Normal %s"] = "Обычно %s"
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Пока ничего не получено - сканирования приходят, когда кто-то, с кем вы делитесь, выполняет полное сканирование."
L["Notifications"] = "Уведомления"
L["Off"] = "Выкл."
L["Off by default: loot and raid addons (e.g. Gargul, AHDB) use modified clicks on items and links. With the AME window open, Shift-click an item to chart it."] =
  "По умолчанию выключено: аддоны для добычи и рейдов (например, Gargul, AHDB) используют клики с модификаторами по предметам и ссылкам. При открытом окне AME Shift-клик по предмету покажет его график."
L["On a watchlist - click to change"] =
  "В списке наблюдения - щёлкните, чтобы изменить"
L["Open"] = "Открытие"
L["Open AME settings"] = "Открыть настройки AME"
L["Open AME together with the auction house"] = "Открывать AME вместе с аукционом"
L["Open item charts with"] = "Открывать графики предметов по"
L["Patient %s"] = "Терпеливо %s"
L["Per item: what it sells for, minus the AH cut, minus what you paid."] =
  "За предмет: цена продажи минус комиссия аукциона минус ваша цена покупки."
L["Pick two different auction houses."] = "Выберите два разных аукциона."
L["Play a sound when a watchlist alert fires"] =
  "Звук при срабатывании оповещения списка"
L["Player"] = "Игрок"
L["Portfolio"] = "Портфель"
L["Portfolio tab"] = "Вкладка «Портфель»"
L["Positions"] = "Позиции"
L["Post at"] = "Выставить по"
L["Posting price"] = "Цена выставления"
L["Posting price: not enough data on this item yet."] =
  "Цена выставления: по этому предмету пока мало данных."
L["Pressure building"] = "Нарастающее давление"
L["Price"] = "Цена"
L["Price each"] = "Цена за шт."
L["Profit"] = "Прибыль"
L["Profit as a share of what you paid. 50% means every 10g spent comes back as 15g."] =
  "Прибыль как доля от уплаченного. 50% значит, что каждые потраченные 10 з возвращаются как 15 з."
L["Purchases"] = "Покупки"
L["Qty"] = "Кол-во"
L["Quick %s"] = "Быстро %s"
L["Rare+"] = "Редкое+"
L["Reading the numbers"] = "Как читать цифры"
L["Realized profit"] = "Реализованная прибыль"
L["Realized profit, 7 days"] = "Реализованная прибыль, 7 дней"
L["Rebuild market index"] = "Перестроить рыночный индекс"
L["Recently heard from"] = "Недавно на связи"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Пересчитывает 30-дневные сводки для скринера, подсказок и оповещений."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Записывает цены аукциона из каждого вашего сканирования и поиска (родные API; работает с любым аддоном-сканером), отдельно для каждого игрового мира и аукциона."
L["Reload UI"] = "Перезагрузить UI"
L["Requests"] = "Запросы"
L["Reset"] = "Сбросить"
L["Run self-test"] = "Запустить самопроверку"
L["SELL"] = "ПРОДАТЬ"
L["SELL signal at %s"] = "Сигнал ПРОДАТЬ по %s"
L["Score"] = "Оценка"
L["Search"] = "Поиск"
L["Search items..."] = "Поиск предметов..."
L["Seen in 3 days"] = "Видели за 3 дня"
L["Seen in 7 days"] = "Видели за 7 дней"
L["Seen today/yesterday"] = "Видели сегодня/вчера"
L["Sell"] = "Продать"
L["Sell at"] = "Продать в"
L["Sellers piling in"] = "Наплыв продавцов"
L["Sellers withdrawing"] = "Уход продавцов"
L["Sells for"] = "Продаётся за"
L["Sells per day (estimate)"] = "Продаж в день (оценка)"
L["Sells per day at the sell house"] = "Продаж в день на аукционе продажи"
L["Sells/d"] = "Прод./д"
L["Settings"] = "Настройки"
L["Share full scans with my guild (members running AME)"] =
  "Делиться полными сканированиями с гильдией (у кого есть AME)"
L["Share with guild"] = "Делиться с гильдией"
L["Share with trusted players (below)"] = "Делиться с доверенными игроками (ниже)"
L["Sharing"] = "Обмен"
L["Sharing settings are on the Sync tab."] =
  "Настройки обмена - на вкладке «Синхронизация»."
L["Shift-click to search the auction house"] = "Shift-клик - поиск на аукционе"
L["Shortage"] = "Дефицит"
L["Show AME prices in item tooltips"] = "Показывать цены AME в подсказках предметов"
L["Show minimap button"] = "Показывать кнопку у миникарты"
L["Signal"] = "Сигнал"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Сигналы и оценка сравнивают предмет с его собственной историей, поэтому для осмысленного результата нужна неделя данных или больше. Выше всех оцениваются дешёвые И стабильные (низкая волатильность) предметы. Падение предложения при неизменной цене часто бывает хорошим ранним признаком. Всё это не совет - рынки могут вести себя странно довольно долго."
L["Sold / bought"] = "Продано / куплено"
L["Spent with you"] = "Потрачено у вас"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  'Отмечайте предметы звездой, чтобы добавить их в список наблюдения; создавайте новые списки кнопкой "+ Новый список" на боковой панели (ПКМ по списку - поделиться им с гильдией или удалить; общие списки членов гильдии отображаются под вашими). На странице предмета задайте оповещение: ниже или выше цены в золоте или при появлении сигнала покупки/продажи. Оповещения проверяются после каждого сканирования и выводятся в чат со звуком.'
L["Steady demand"] = "Устойчивый спрос"
L["Suppliers"] = "Поставщики"
L["Supply"] = "Предложение"
L["Supply  ·  sells/day"] = "Предложение  ·  прод./день"
L["Swap"] = "Поменять"
L["Switch to the Item tab when you put an item up for sale"] =
  "Переключаться на вкладку «Предмет», когда вы выставляете предмет на продажу"
L["Sync"] = "Синхронизация"
L["Sync is unavailable: the AceComm library didn't load."] =
  "Синхронизация недоступна: библиотека AceComm не загрузилась."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "Средняя дневная рыночная цена за выбранный период (Настройки > Период усреднения, по умолчанию 7 дней). Сравните её с сегодняшней рыночной ценой, чтобы понять, дёшев предмет сейчас или дорог."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "Самый дешёвый лот на аукционе, где вы покупаете, - столько стоят первые штуки."
L["The cheapest single listing seen in the latest data."] =
  "Самый дешёвый отдельный лот в последних данных."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "Рыночная цена на аукционе, где вы продаёте: за сколько предмет обычно там продаётся."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Shift-click any item (bags, chat, the AH) while this window is open to chart it, or set a modifier click in Settings."] =
  "График цен: рыночная цена, самый дешёвый лот, среднее за 7 дней и предложение. Переключитесь на свечи для трейдерского вида. Колесо мыши - масштаб, перетаскивание - сдвиг, двойной клик - сброс. Shift-клик по любому предмету (сумки, чат, аукцион) при открытом окне покажет его график; клик с модификатором можно задать в настройках."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Этот рынок: %d дн. истории, %d недавних сканирований хранятся целиком"
L["Tightening"] = "Сжатие предложения"
L["Time left"] = "Осталось времени"
L["Top buy signals"] = "Лучшие сигналы покупки"
L["Total"] = "Итого"
L["Trusted"] = "Доверенные"
L["Trusted (%d)"] = "Доверенные (%d)"
L["Trusted players"] = "Доверенные игроки"
L["Type %d"] = "Тип %d"
L["Unblock"] = "Разблокировать"
L["Uncommon+"] = "Необычное+"
L["Unrealized"] = "Нереализов."
L["Unrealized profit"] = "Нереализованная прибыль"
L["VENDOR"] = "ТОРГОВЕЦ"
L["VENDOR: after the AH cut and the listing deposit, the auction house pays less than a vendor would - sell it to a vendor."] =
  "ТОРГОВЕЦ: после комиссии аукциона и залога аукцион даст меньше, чем торговец, - продайте торговцу."
L["Value"] = "Стоимость"
L["Vendor"] = "Торговец"
L["Volatility"] = "Волатильность"
L["WAIT"] = "ЖДАТЬ"
L["Watch"] = "Следить"
L["Watching"] = "Слежу"
L["Watchlists and alerts"] = "Списки наблюдения и оповещения"
L["Weak demand"] = "Слабый спрос"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "Всё, что есть у ваших персонажей, по ценам рынка вашей фракции, с ценой покупки и нереализованной прибылью для купленного на аукционе, сигналом Купить/Держать/Продать и временем на продажу. В журнале - ваши продажи и покупки на аукционе, записанные по почте аукциона, когда вы открываете почтовый ящик."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Сколько стоит выставить одну штуку на аукционе продажи сразу: доля цены продажи торговцу (аукцион фракции 5/20/60% за 2/8/24 часа, аукцион гоблинов - в пять раз больше), минимум 1 серебряная. Залог возвращается при продаже и теряется, если предмет не продан, - так что высокий залог на медленно продающемся предмете - реальный риск."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "За сколько предмет обычно продаётся прямо сейчас. По полным данным лотов это среднее самых дешёвых 15-30% предложения на аукционе, что отсекает несколько дешёвых или абсурдных лотов. По сводке просмотра (что многие сканеры делают по умолчанию) известен только самый дешёвый лот, поэтому тогда это минимальная цена."
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "По какой цене выставлять, чтобы предмет продался за время лота, - вместо того чтобы перебивать самый дешёвый лот на 1 медь. Покупатели сначала берут самые дешёвые лоты, поэтому AME считает единицы впереди вас по каждой цене, скорость продаж предмета и то, как часто новые лоты перебивают вашу цену, и сопоставляет шанс продажи с залогом, который вы теряете, если предмет не продастся. Быстро - почти наверняка продастся за несколько часов, Обычно - лучшая цена с учётом шанса, Терпеливо - самая высокая цена, по которой предмет ещё продаётся примерно в половине случаев. AME изучает поведение каждого предмета по вашим сканированиям (часы пик, дни недели, насколько жёстко конкурируют продавцы) и по вашим собственным лотам: если предметы по его ценам часто истекают, он становится осторожнее с этим предметом. При малом количестве данных он опирается на похожие предметы; полосы показывают, сколько он знает."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Сколько вы заплатили за штуку для купленных на аукционе штук (первыми продаются самые старые покупки). У добытых или созданных предметов нет цены покупки."
L["When"] = "Когда"
L["Where the data comes from"] = "Откуда берутся данные"
L["Window colours"] = "Цвета окна"
L["Window scale"] = "Масштаб окна"
L["You haven't blocked anyone."] = "Вы никого не заблокировали."
L["You spent"] = "Ваши траты"
L["You'd receive (after the cut)"] = "Вы получите (после комиссии)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Ваши активные аукционы на всех персонажах (на момент, когда каждый из них последний раз открывал аукцион)."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "Ваши твинки на этой учётной записи Battle.net уже делят всё: история AME сохраняется для всей учётной записи. Добавьте игроков в доверенные, чтобы обмениваться сканированиями с друзьями или со своими персонажами на других учётных записях. Передаются только ваш рынок и аукцион, а сканирования, сильно расходящиеся с вашими ценами, отклоняются."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "Письма аукциона в этом клиенте не называют другого игрока (аукцион сохраняет анонимность), так что показать некого."
L["a list needs a name"] = "у списка должно быть название"
L["a list with that name already exists"] = "список с таким названием уже есть"
L["a week+"] = "неделя+"
L["above g"] = "выше g"
L["announced %d, served %d, received %d, rejected %d"] =
  "объявлено %d, отдано %d, получено %d, отклонено %d"
L["auctionator history import"] = "импорт истории из Auctionator"
L["average period"] = "период усреднения"
L["awaiting mail"] = "ждёт письма"
L["backfill"] = "дозаполнение истории"
L["background jobs: %s"] = "фоновые задачи: %s"
L["below g"] = "ниже g"
L["blocked"] = "заблокирован"
L["blocked %s"] = "%s заблокирован"
L["bought"] = "куплено"
L["chart library + window"] = "библиотека графиков + окно"
L["codec+compress 6.4k items"] = "кодек+сжатие 6.4k предметов"
L["could not load %s: %s"] = "не удалось загрузить %s: %s"
L["could not load history addon"] = "не удалось загрузить аддон истории"
L["couldn't start an auction house search for %s"] =
  "не удалось начать поиск на аукционе для %s"
L["data"] = "данные"
L["deposit %s"] = "залог %s"
L["done %s"] = "готово %s"
L["down  (wick = cheapest)"] = "падение  (тень = самый дешёвый)"
L["dropped to %s (alert at %s)"] = "упала до %s (оповещение при %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "кодирование %.0f мс, сжатие %.0f мс, распаковка+декодирование %.0f мс, %d КБ -> %d КБ"
L["ended?"] = "завершён?"
L["enter a character name"] = "введите имя персонажа"
L["guild"] = "гильдию"
L["guild sync"] = "синхронизация гильдии"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "синхронизация гильдии: %s, объявлено %d, отдано %d, получено %d, отклонено %d"
L["heard %s"] = "на связи %s"
L["history addon"] = "аддон истории"
L["history import from Auctionator failed: %s"] = "импорт истории из Auctionator не удался: %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "импорт истории из Auctionator выполняется только на аукционе вашей фракции (его данные смешивают все аукционы)."
L["history lookup (cold)"] = "запрос истории (холодный)"
L["history: %d raw scans, %d days, %.0f KB"] =
  "история: %d сырых сканирований, %d дн., %.0f КБ"
L["idle"] = "нет"
L["imported %d days of price history from Auctionator into %s"] =
  "импортировано %d дн. истории цен из Auctionator в %s"
L["item %d: %d points in %.1f ms"] = "предмет %d: %d точек за %.1f мс"
L["item from latest scan has no daily points"] =
  "у предмета из последнего сканирования нет дневных точек"
L["item not loaded yet - try again in a moment"] =
  "предмет ещё не загружен - попробуйте чуть позже"
L["just now"] = "только что"
L["last error (%s, %s): %s"] = "последняя ошибка (%s, %s): %s"
L["last full scan"] = "последнее полное сканирование"
L["last full scan: %d items, %s ago"] =
  "последнее полное сканирование: %d предметов, %s назад"
L["last seen %s"] = "последний раз %s"
L["libraries"] = "библиотеки"
L["listed"] = "в продаже"
L["loaded"] = "загружено"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] =
  "загружено за %s мс, фрагментов: %d, %.0f КБ дневной истории"
L["loading history..."] = "загрузка истории..."
L["loading item names %d/%d"] = "загрузка названий предметов %d/%d"
L["lowest"] = "минимум"
L["margin %"] = "маржа %"
L["market"] = "рынок"
L["market %s, history %s"] = "рынок %s, история %s"
L["market index"] = "рыночный индекс"
L["max g"] = "макс. g"
L["min g"] = "мин. g"
L["more is listed than sells in one listing time: only the lowest price sells soon"] =
  "выставлено больше, чем продаётся за время лота: скоро продастся только самая низкая цена"
L["never"] = "никогда"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "полное сканирование ещё не записано: откройте аукцион и выполните полное сканирование (вашего аддона-сканера или игры)"
L["no history for %s in %s"] = "нет истории для %s в %s"
L["no scans in this shard yet"] = "в этом фрагменте ещё нет сканирований"
L["none"] = "нет"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "пока нет: откройте аукцион и выполните полное сканирование, затем снова запустите /ame selftest"
L["not built yet (needs history)"] = "ещё не построен (нужна история)"
L["not heard yet"] = "ещё не на связи"
L["not in a guild"] = "вы не в гильдии"
L["not loaded"] = "не загружено"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "здесь ничего не импортировано (только с данными Auctionator, на аукционе вашей фракции)"
L["off"] = "выкл."
L["on"] = "вкл."
L["on buy/sell signal"] = "при сигнале покупки/продажи"
L["on, but you're not in a guild"] = "вкл., но вы не в гильдии"
L["open the auction house first"] = "сначала откройте аукцион"
L["profit g"] = "прибыль g"
L["reading full scan (%d listings) in the background..."] =
  "чтение полного сканирования (%d лотов) в фоне..."
L["received a full scan from %s via sync (%d items, %s)"] =
  "получено полное сканирование от %s через синхронизацию (%d предметов, %s)"
L["recorded full scan: %d items from %d listings (%s)"] =
  "полное сканирование записано: %d предметов из %d лотов (%s)"
L["rose to %s (alert at %s)"] = "выросла до %s (оповещение при %s)"
L["round trip mismatch"] = "несовпадение при обратном преобразовании"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "конвейер сканирования: %d запросов, %d событий (%d после последнего запроса), чтение %s, прервано %d; приём requested=%s reading=%s"
L["scan read failed:"] = "ошибка чтения сканирования:"
L["score"] = "оценка"
L["score %+d"] = "оценка %+d"
L["search"] = "поиск"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "самопроверка завершена:\n%s\n\nПерезагрузить интерфейс сейчас, чтобы сохранить результаты?"
L["selftest starting (this may pause the game for a moment)"] =
  "запуск самопроверки (игра может ненадолго замереть)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "самопроверка: пройдено %d, предупреждений %d, ошибок %d. Перезагрузитесь, чтобы сохранить результаты (/reload)."
L["sells"] = "продажи"
L["shard"] = "фрагмент"
L["shared"] = "общий"
L["sharing"] = "обмен"
L["signal"] = "сигнал"
L["sold"] = "продано"
L["still building in the background"] = "ещё строится в фоне"
L["storing %s scan failed:"] = "не удалось сохранить сканирование (%s):"
L["supply"] = "предложение"
L["sync errors: %d (last: %s)"] = "ошибки синхронизации: %d (последняя: %s)"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "аукцион закрылся до того, как AME дочитал полное сканирование; оно не записано."
L["today"] = "сегодня"
L["turned off in settings"] = "отключено в настройках"
L["unknown command, try /ame help"] = "неизвестная команда, попробуйте /ame help"
L["unlikely to sell soon: consider holding"] =
  "вряд ли продастся скоро: лучше придержать"
L["up"] = "рост"
L["updating market data..."] = "обновление рыночных данных..."
L["usage: /ame item <item link or itemID>"] =
  "использование: /ame item <ссылка на предмет или itemID>"
L["via %s, %s"] = "через %s, %s"
L["volatility"] = "волатильность"
L["waiting for them to approve"] = "ждём их одобрения"
L["wants to share, %s"] = "хочет делиться, %s"
L["well below its usual price"] = "намного ниже обычной цены"
L["whisper"] = "шёпот"
L["window created, market tab rendered"] = "окно создано, вкладка рынка отрисована"
L["yesterday"] = "вчера"
L["you bought"] = "ваши покупки"
L["you sold"] = "ваши продажи"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "вы на аукционе покупки: «Поиск» (или Shift-клик по строке), чтобы купить"
L["~%d days"] = "~%d дн."
L["~%dh"] = "~%d ч"
