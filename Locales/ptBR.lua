-- Portuguese (Brazil). Keys are the English texts (Locales/enUS.lua);
-- anything not translated here falls back to English.
-- Translations are AI-made: native speakers, please review (CurseForge's translation tool, or a pull request).
local ADDON = ...
local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:NewLocale(ADDON, "ptBR")
if not L then
  return
end

L["%d AH sales and purchases in the last 90 days. AME records them from auction mail: open your mailbox to catch new ones."] =
  "%d vendas e compras na CL nos últimos 90 dias. O AME as registra a partir do correio de leilão: abra sua caixa de correio para capturar as novas."
L["%d active auctions on your characters, as of the last time each opened the auction house. Sales show up in the ledger right away and are settled when the auction mail arrives."] =
  "%d leilões ativos nos seus personagens, desde a última vez que cada um abriu a casa de leilões. As vendas aparecem no extrato na hora e são liquidadas quando chega o correio do leilão."
L["%d ahead"] = "%d à frente"
L["%d auctions"] = "%d leilões"
L["%d customers in the last 90 days, by gold spent with you (from auction mail)."] =
  "%d clientes nos últimos 90 dias, por ouro gasto com você (pelo correio de leilão)."
L["%d days"] = "%d dias"
L["%d days ago"] = "há %d dias"
L["%d h ago"] = "há %d h"
L["%d h listings"] = "leilões de %d h"
L["%d items  ·  showing %d-%d  ·  index from %s"] = "%d itens  ·  mostrando %d-%d  ·  índice de %s"
L["%d items from %s listings, stored %s ms after the scan request"] =
  "%d itens de %s anúncios, armazenados %s ms após a solicitação de varredura"
L["%d items not searchable yet (names loading)"] = "%d itens ainda não pesquisáveis (carregando nomes)"
L["%d items summarized"] = "%d itens resumidos"
L["%d items summarized in %s ms wall"] = "%d itens resumidos em %s ms reais"
L["%d min ago"] = "há %d min"
L["%d of %d known prices differ more than %dx from ours"] = "%d de %d preços conhecidos diferem mais de %dx dos nossos"
L["%d passed, %d warnings, %d failed"] = "%d aprovados, %d avisos, %d falhas"
L["%d positions on %d character. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posições em %d personagem. As bolsas se atualizam enquanto você joga; abra seu banco e a casa de leilões para incluir itens do banco e leilões ativos."
L["%d positions on %d characters. Bags update as you play; open your bank and the auction house to include bank items and active auctions."] =
  "%d posições em %d personagens. As bolsas se atualizam enquanto você joga; abra seu banco e a casa de leilões para incluir itens do banco e leilões ativos."
L["%d routes  ·  buy at %s, sell at %s: %d%% cut, deposits for %dh listings"] =
  "%d rotas  ·  compre em %s, venda em %s: %d%% de taxa, depósitos de leilões de %dh"
L["%d scans in 7 days"] = "%d varreduras em 7 dias"
L["%d scans/7d, %s"] = "%d varreduras/7d, %s"
L["%d suppliers in the last 90 days, by gold you spent with them (from auction mail)."] =
  "%d fornecedores nos últimos 90 dias, por ouro que você gastou com eles (pelo correio de leilão)."
L["%d watched items have no price history here yet"] = "%d itens observados ainda não têm histórico de preços aqui"
L["%d-day average"] = "Média de %d dias"
L["%dd avg"] = "Méd. %dd"
L["%dx off usual"] = "%dx fora do normal"
L["%s  -  created by Tyken Evanion  -  PvP Horde, WoW Forever"] =
  "%s  -  criado por Tyken Evanion  -  PvP Horda, WoW Forever"
L["%s  ·  %d days of history  ·  data %s %s%s%s"] = "%s  ·  %d dias de histórico  ·  dados %s %s%s%s"
L["%s %s: min %s, market %s, qty %d (%d samples)"] = "%s %s: mín. %s, mercado %s, qtd. %d (%d amostras)"
L["%s latest (%s): min %s, market %s, %d units in %d auctions"] =
  "%s mais recente (%s): mín. %s, mercado %s, %d unidades em %d leilões"
L["%s wants to share auction prices with you. Open |cffffffff/ame|r > Sync to approve."] =
  "%s quer compartilhar preços de leilão com você. Abra |cffffffff/ame|r > Sincronizar para aprovar."
L["(each point is one scan)"] = "(cada ponto é uma varredura)"
L["+ %d more"] = "+ %d a mais"
L[", %d scans received"] = ", %d varreduras recebidas"
L["/ame - open the window  ·  /ame <item link> - chart an item  ·  Alt-click an item - chart it"] =
  "/ame - abrir a janela  ·  /ame <link do item> - gráfico de um item  ·  Alt-clique em um item - ver o gráfico"
L["/ame - open the window.   /ame <item link> - chart an item.   /ame status - data and sync status.   /ame config - settings.   /ame selftest - check everything is working."] =
  "/ame - abre a janela.   /ame <link do item> - gráfico de um item.   /ame status - status dos dados e da sincronização.   /ame config - configurações.   /ame selftest - verifica se tudo está funcionando."
L["/ame item <link> - print history  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"] =
  "/ame item <link> - mostrar histórico  ·  /ame status  ·  /ame selftest  ·  /ame backfill  ·  /ame config"
L["/week"] = "/semana"
L["1 day"] = "1 dia"
L["30 days: sold / bought"] = "30 dias: vendido / comprado"
L["7-day change"] = "Variação em 7 dias"
L["7d"] = "7d"
L["7d average"] = "Média de 7 dias"
L["7d avg"] = "Méd. 7d"
L["<1h"] = "<1 h"
L["A screener over every item with history. Pick a category or watchlist on the left, search by name, filter by quality, price range or signal, and click a column to sort. Hover a column header for what it means. Click a row to open its chart; click the star to watch it."] =
  "Um filtro de todos os itens com histórico. Escolha uma categoria ou lista de observação à esquerda, pesquise pelo nome, filtre por qualidade, faixa de preço ou sinal, e clique numa coluna para ordenar. Passe o mouse sobre o cabeçalho de uma coluna para ver o que significa. Clique numa linha para abrir o gráfico; clique na estrela para observar o item."
L["AH cut"] = "Taxa da CL"
L["AME alert: %s %s"] = "Alerta do AME: %s %s"
L["AME listens to the game's own auction house APIs, so every scan and search you run is recorded - from the default auction house window or any scanning addon (it works well with addons like Auctionator). Nothing extra is scanned. History is kept per market (realm or Forever ruleset) and auction house, and guild members running AME share their full scans automatically."] =
  "O AME escuta as próprias APIs de casa de leilões do jogo, então toda varredura e pesquisa que você faz é registrada - pela janela padrão da casa de leilões ou por qualquer addon de varredura (funciona bem com addons como o Auctionator). Nada a mais é varrido. O histórico é mantido por mercado (reino ou regras do Forever) e casa de leilões, e membros da guilda que usam o AME compartilham suas varreduras completas automaticamente."
L["AceComm not available: sync disabled"] = "AceComm indisponível: sincronização desativada"
L["Activity"] = "Atividade"
L["Add"] = "Adicionar"
L["Alert when"] = "Alertar quando"
L["Alert:"] = "Alerta:"
L["All"] = "Tudo"
L["All items"] = "Todos os itens"
L["All markets: %d, %.0f KB of compressed daily history"] =
  "Todos os mercados: %d, %.0f KB de histórico diário comprimido"
L["Alliance AH"] = "CL Aliança"
L["Alliance blue"] = "Azul Aliança"
L["Always show full tooltip details (otherwise hold Shift)"] =
  "Sempre mostrar todos os detalhes na dica (senão, segure Shift)"
L["An opportunity ranking from -100 to +100. Higher means the item is further below its usual price, on a stable item, with an upward trend. Around 0 means a normal price; negative means pricier than usual. Sort by it to find bargains quickly."] =
  "Uma classificação de oportunidade de -100 a +100. Mais alto significa que o item está mais abaixo do preço habitual, é estável e tem tendência de alta. Perto de 0 é um preço normal; negativo significa mais caro que o habitual. Ordene por ela para achar pechinchas rapidamente."
L["Announce recorded full scans in chat"] = "Anunciar no chat as varreduras completas registradas"
L["Announced %d times, served %d scans, received %d, rejected %d"] =
  "Anunciado %d vezes, %d varreduras servidas, %d recebidas, %d rejeitadas"
L["Any age"] = "Qualquer idade"
L["Any quality"] = "Qualquer qualidade"
L["Approve"] = "Aprovar"
L["Arbitrage"] = "Arbitragem"
L["Arbitrage tab"] = "Aba Arbitragem"
L["Asked %s to share. They'll see a request in their Sync tab."] =
  "Pedido enviado a %s para compartilhar. Ele verá uma solicitação na aba Sincronizar."
L["Asking prices"] = "Preços pedidos"
L["At market price"] = "A preço de mercado"
L["Auction house"] = "Casa de leilões"
L["Auction house cut"] = "Taxa da casa de leilões"
L["Auctionator not installed: nothing to import (scans are recorded from the game either way)"] =
  "Auctionator não instalado: nada para importar (as varreduras são registradas pelo jogo de qualquer forma)"
L["Auctions"] = "Leilões"
L["Average"] = "Média"
L["Average cost"] = "Custo médio"
L["Avg cost"] = "Custo méd."
L["BUY"] = "COMPRAR"
L["BUY signal at %s"] = "Sinal de COMPRA a %s"
L["BUY: today's price is unusually low for this item - at least 1.5 standard deviations below its own 30-day average. SELL: unusually high by the same measure. HOLD: within its normal range - keep it if you own it, no edge to buy. WAIT: cheap, but sellers are dumping - wait for the bottom. Needs 7+ days of history (\"-\" until then). The market phase reads the week's price move against supply: shortage, steady demand, sellers piling in, tightening, balanced, pressure building, sellers withdrawing, weak demand or dumping. It compares the item with itself, and it's a hint, not financial advice."] =
  'COMPRAR: o preço de hoje está incomumente baixo para este item - pelo menos 1,5 desvio padrão abaixo da sua própria média de 30 dias. VENDER: incomumente alto pela mesma medida. MANTER: dentro da faixa normal - mantenha se tiver, sem vantagem em comprar. AGUARDAR: barato, mas os vendedores estão despejando - espere o fundo. Precisa de 7+ dias de histórico ("-" até lá). A fase de mercado compara o movimento semanal do preço com a oferta: escassez, demanda firme, vendedores chegando em massa, oferta apertando, equilíbrio, pressão crescente, vendedores recuando, demanda fraca ou despejo. Ela compara o item consigo mesmo, e é uma dica, não um conselho financeiro.'
L["Balanced"] = "Equilíbrio"
L["Block"] = "Bloquear"
L["Blocked"] = "Bloqueados"
L["Buy at"] = "Comprar em"
L["By your guild officers: %s"] = "Pelos oficiais da sua guilda: %s"
L["Cancel"] = "Cancelar"
L["Candles"] = "Candles"
L["Change this if another addon (e.g. AHDB) also uses Alt-click on items."] =
  "Altere isto se outro addon (ex.: AHDB) também usa Alt-clique em itens."
L["Character"] = "Personagem"
L["Character name, e.g. First Last"] = "Nome do personagem, ex.: Nome Sobrenome"
L["Chart style"] = "Estilo do gráfico"
L["Checks every part of AME and offers a reload so the results are saved."] =
  "Verifica todas as partes do AME e oferece recarregar para salvar os resultados."
L["Class %d"] = "Classe %d"
L["Click a row to open its price chart. Click the star to add it to a watchlist. The bars after the name show how much to trust the numbers: 3 green = plenty of recent scans, 2 amber = some, 1 red = few or old."] =
  "Clique numa linha para abrir o gráfico de preços. Clique na estrela para adicioná-lo a uma lista de observação. As barras após o nome mostram quanto confiar nos números: 3 verdes = muitas varreduras recentes, 2 âmbar = algumas, 1 vermelha = poucas ou antigas."
L["Close"] = "Fechar"
L["Commands"] = "Comandos"
L["Common+"] = "Comum+"
L["Copy to my watchlists"] = "Copiar para minhas listas"
L["Could not load history: %s"] = "Não foi possível carregar o histórico: %s"
L["Customers"] = "Clientes"
L["Data"] = "Dados"
L["Data quality"] = "Qualidade dos dados"
L["Days to sell"] = "Dias para vender"
L["Days where an item's price is this many times above (or below) its neighbouring days are left out of the screener, signals, alerts and charts - typically one listing at a 1000% markup in a thin market. Within a full scan, AME already ignores expensive listings: market price uses the cheapest part of the supply."] =
  "Dias em que o preço de um item fica tantas vezes acima (ou abaixo) dos dias vizinhos são deixados de fora do filtro, sinais, alertas e gráficos - normalmente um único anúncio com 1000% de ágio num mercado pouco movimentado. Dentro de uma varredura completa, o AME já ignora anúncios caros: o preço de mercado usa a parte mais barata da oferta."
L["Decline"] = "Recusar"
L["Delete list..."] = "Excluir lista..."
L['Delete the watchlist "%s"?'] = 'Excluir a lista de observação "%s"?'
L["Deposit"] = "Depósito"
L["Deposits for"] = "Depósitos de"
L["Depth"] = "Profundidade"
L["Display"] = "Exibição"
L["Dumping"] = "Despejo"
L["Each candle covers one or more days. It opens at the previous candle's close and closes at the market price; green closed higher, red lower. The thin wick reaches down to the cheapest listing seen."] =
  "Cada candle cobre um ou mais dias. Abre no fechamento do candle anterior e fecha no preço de mercado; verde fechou mais alto, vermelho mais baixo. O pavio fino desce até o anúncio mais barato visto."
L["Epic+"] = "Épico+"
L["Estimated units sold per day where you'd sell. Compare it with how many you plan to buy: if it sells 5 a day, 100 will take weeks."] =
  "Unidades vendidas por dia (estimativa) onde você venderia. Compare com quantas você pretende comprar: se vende 5 por dia, 100 vão levar semanas."
L["Everything your characters hold - bags, bank and active auctions - at your faction auction house's market price. Bank items and auctions are counted as of the last time you opened the bank / auction house."] =
  "Tudo o que seus personagens têm - bolsas, banco e leilões ativos - ao preço de mercado da casa de leilões da sua facção. Itens do banco e leilões contam desde a última vez que você abriu o banco / a casa de leilões."
L["Faction auction houses"] = "Casas de leilões de facção"
L["Follow market"] = "Seguir o mercado"
L["For units you bought on the auction house: what they're worth now at market price minus what you paid. It becomes real profit when you sell."] =
  "Para unidades que você comprou na casa de leilões: quanto valem agora a preço de mercado menos o que você pagou. Vira lucro real quando você vende."
L["From your auction sales: what you received after the AH cut, minus what you paid for those units (oldest purchases first). Sales of looted or crafted items count fully."] =
  "Das suas vendas em leilão: o que você recebeu após a taxa da CL, menos o que pagou por essas unidades (compras mais antigas primeiro). Vendas de itens saqueados ou criados contam integralmente."
L["Goblin AH"] = "CL Goblin"
L["Goblin auction houses"] = "Casas de leilões goblins"
L["Goblin gold"] = "Ouro goblin"
L["Gold received from auction sales (after the cut) and gold spent on auction purchases in the last 30 days."] =
  "Ouro recebido de vendas em leilão (após a taxa) e ouro gasto em compras em leilão nos últimos 30 dias."
L["Guide"] = "Guia"
L['Guild officers can block players for everyone: add a line "%s" to the guild info.'] =
  'Oficiais da guilda podem bloquear jogadores para todos: adicione uma linha "%s" às informações da guilda.'
L["Guild watchlists"] = "Listas da guilda"
L["Guild: %s"] = "Guilda: %s"
L["HOLD"] = "MANTER"
L["Held"] = "Em mãos"
L["High"] = "Máxima"
L["History not loaded yet."] = "Histórico ainda não carregado."
L["Hold Shift for more AME data"] = "Segure Shift para mais dados do AME"
L["Holdings value"] = "Valor das posições"
L["Horde AH"] = "CL Horda"
L["Horde red"] = "Vermelho Horda"
L["How fast the item moves: units that disappeared between consecutive full scans of this auction house, per day, over the last week. It counts sold, cancelled and expired listings, and new listings hide some sales, so treat it as a rough guide. A cheap item that never sells is a trap; a high number means you can sell a stack quickly. Needs a few full scans on the same day to show."] =
  "Com que rapidez o item gira: unidades que sumiram entre varreduras completas consecutivas desta casa de leilões, por dia, na última semana. Conta anúncios vendidos, cancelados e expirados, e novos anúncios escondem algumas vendas, então use como um guia aproximado. Um item barato que nunca vende é uma armadilha; um número alto significa que você vende uma pilha rápido. Precisa de algumas varreduras completas no mesmo dia para aparecer."
L["How long selling everything you hold would take at the item's current sell rate (estimate)."] =
  "Quanto tempo levaria para vender tudo o que você tem no ritmo de venda atual do item (estimativa)."
L["How many are listed in the latest data. On the item page the % next to it is the weekly supply trend: falling supply often comes before rising prices."] =
  "Quantos estão anunciados nos dados mais recentes. Na página do item, o % ao lado é a tendência semanal da oferta: oferta em queda costuma vir antes de alta nos preços."
L["How many units you can buy at the buy auction house before the route stops paying, and the total profit: every listing priced below what one sells for after the cut. It needs the item's listings, so search the item at the buy house first (the Search button does it) - it then stays for 6 hours. Selling that many still takes time: check Sells/d."] =
  "Quantas unidades você pode comprar na casa de compra antes que a rota deixe de compensar, e o lucro total: cada anúncio com preço abaixo do que uma unidade rende após a taxa. Precisa dos anúncios do item, então pesquise o item primeiro na casa de compra (o botão Pesquisar faz isso) - eles ficam guardados por 6 horas. Vender tudo isso ainda leva tempo: confira Vendas/d."
L["How much the market price moved compared with 7 days of data ago. Green is up, red is down."] =
  "Quanto o preço de mercado se moveu em comparação com 7 dias de dados atrás. Verde é alta, vermelho é queda."
L["How much the price jumps from day to day (the spread of daily % changes over 30 days). Low numbers mean a stable, predictable item; high numbers mean risky swings - and bigger opportunities."] =
  "Quanto o preço salta de um dia para o outro (a dispersão das variações diárias em % ao longo de 30 dias). Números baixos indicam um item estável e previsível; números altos, oscilações arriscadas - e oportunidades maiores."
L["How old the older of the two prices is. Fresh data on both sides makes a route trustworthy - scan both auction houses (alts on this account count) before buying."] =
  "A idade do mais antigo dos dois preços. Dados recentes dos dois lados tornam uma rota confiável - faça varreduras nas duas casas de leilões (alts desta conta contam) antes de comprar."
L["If Auctionator is installed: imports its recent daily prices for days AME has no data for (faction AH)."] =
  "Se o Auctionator estiver instalado: importa os preços diários recentes dele para os dias em que o AME não tem dados (CL de facção)."
L["Ignore outrageous prices"] = "Ignorar preços absurdos"
L["Import history from Auctionator"] = "Importar histórico do Auctionator"
L["Item"] = "Item"
L["Item name, ID, or Shift-click an item"] = "Nome do item, ID ou Shift-clique num item"
L["Item tab"] = "Aba Item"
L["Items"] = "Itens"
L["Items tracked"] = "Itens acompanhados"
L["Items you can buy at one auction house and sell at another for a profit after the AH cut - e.g. your faction's AH and the goblin AH (cross-faction). Each auction house keeps its own history, so scan both (alts on this account count). Hover the columns for details."] =
  "Itens que você pode comprar numa casa de leilões e vender em outra com lucro após a taxa - ex.: a CL da sua facção e a CL Goblin (entre facções). Cada casa de leilões tem seu próprio histórico, então faça varreduras nas duas (alts desta conta contam). Passe o mouse sobre as colunas para detalhes."
L['Keep the AH open until AME says "recorded full scan".'] =
  'Mantenha a CL aberta até o AME dizer "varredura completa registrada".'
L["Last"] = "Última"
L["Last full scan"] = "Última varredura completa"
L["Last full scan: %d items, %s"] = "Última varredura completa: %d itens, %s"
L["Last received: %d items from %s, %s"] = "Última recebida: %d itens de %s, %s"
L["Last rejected:"] = "Última rejeitada:"
L["Ledger"] = "Extrato"
L["Left-click: window   Right-click: settings"] = "Clique esquerdo: janela   Clique direito: configurações"
L["LibAMEChart-1.0 not loaded"] = "LibAMEChart-1.0 não carregada"
L["LibDeflate not loaded"] = "LibDeflate não carregada"
L["Listed at the buy house / at the sell house. Plenty to buy and little to compete with where you sell is ideal; a big gap on one listing at the buy house may be gone fast."] =
  "Anunciados na casa de compra / na casa de venda. Muito para comprar e pouca concorrência onde você vende é o ideal; uma grande diferença num único anúncio na casa de compra pode sumir rápido."
L["Listed on the AH now"] = "Na CL agora"
L["Listed on the auction house now"] = "Na casa de leilões agora"
L["Loading history..."] = "Carregando histórico..."
L["Loading market data..."] = "Carregando dados de mercado..."
L["Loading recent scans..."] = "Carregando varreduras recentes..."
L["Low (cheapest)"] = "Mínima (mais barato)"
L["Lowest"] = "Menor"
L["Margin"] = "Margem"
L["Market"] = "Mercado"
L["Market price"] = "Preço de mercado"
L["Market tab"] = "Aba Mercado"
L["Market: %s"] = "Mercado: %s"
L["Mostly"] = "Principalmente"
L["Name for the new watchlist:"] = "Nome da nova lista:"
L["New list"] = "Nova lista"
L["New list..."] = "Nova lista..."
L["No full scan recorded yet."] = "Nenhuma varredura completa registrada ainda."
L["No history for this item yet. Search for it at the auction house, or run a full scan."] =
  "Ainda não há histórico para este item. Pesquise-o na casa de leilões ou faça uma varredura completa."
L["No market data for your faction's auction house yet - scan there to value your holdings."] =
  "Ainda não há dados de mercado da casa de leilões da sua facção - faça uma varredura lá para avaliar suas posições."
L["No one yet."] = "Ninguém ainda."
L["No price history for the %s yet: scan there (any character on this account counts) to compare."] =
  "Ainda não há histórico de preços da %s: faça uma varredura lá (qualquer personagem desta conta serve) para comparar."
L["No price history for the %s yet: scan there (any character on this account counts)."] =
  "Ainda não há histórico de preços da %s: faça uma varredura lá (qualquer personagem desta conta serve)."
L["No scans of this item in the last 2 days. Daily history is on the other ranges."] =
  "Nenhuma varredura deste item nos últimos 2 dias. O histórico diário está nos outros períodos."
L["Nobody yet. Add a friend above - they need AME too, and must approve."] =
  "Ninguém ainda. Adicione um amigo acima - ele também precisa do AME e tem que aprovar."
L["Normal %s"] = "Normal %s"
L["Nothing received yet - scans arrive when someone you share with runs a full scan."] =
  "Nada recebido ainda - as varreduras chegam quando alguém com quem você compartilha faz uma varredura completa."
L["Notifications"] = "Notificações"
L["Off"] = "Desativado"
L["Open"] = "Abertura"
L["Open item charts with"] = "Abrir gráficos de itens com"
L["Patient %s"] = "Paciente %s"
L["Pick two different auction houses."] = "Escolha duas casas de leilões diferentes."
L["Play a sound when a watchlist alert fires"] = "Tocar um som quando um alerta de lista disparar"
L["Player"] = "Jogador"
L["Portfolio"] = "Carteira"
L["Portfolio tab"] = "Aba Carteira"
L["Positions"] = "Posições"
L["Post at"] = "Leiloar por"
L["Posting price"] = "Preço de leilão"
L["Posting price: not enough data on this item yet."] =
  "Preço de leilão: ainda não há dados suficientes sobre este item."
L["Pressure building"] = "Pressão crescente"
L["Price"] = "Preço"
L["Price each"] = "Preço unitário"
L["Profit"] = "Lucro"
L["Qty"] = "Qtd."
L["Quick %s"] = "Rápido %s"
L["Rare+"] = "Raro+"
L["Reading the numbers"] = "Como ler os números"
L["Realized profit"] = "Lucro realizado"
L["Realized profit, 7 days"] = "Lucro realizado, 7 dias"
L["Rebuild market index"] = "Reconstruir índice de mercado"
L["Recently heard from"] = "Contatos recentes"
L["Recomputes the 30-day summaries behind the screener, tooltips and alerts."] =
  "Recalcula os resumos de 30 dias usados pelo filtro, dicas e alertas."
L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."] =
  "Registra os preços da casa de leilões de toda varredura e pesquisa que você faz (APIs nativas; funciona com qualquer addon de varredura), por reino e casa de leilões."
L["Reload UI"] = "Recarregar IU"
L["Requests"] = "Solicitações"
L["Reset"] = "Redefinir"
L["Run self-test"] = "Executar autoteste"
L["SELL"] = "VENDER"
L["SELL signal at %s"] = "Sinal de VENDA a %s"
L["Score"] = "Pontuação"
L["Search"] = "Pesquisar"
L["Search items..."] = "Pesquisar itens..."
L["Seen in 3 days"] = "Visto em 3 dias"
L["Seen in 7 days"] = "Visto em 7 dias"
L["Seen today/yesterday"] = "Visto hoje/ontem"
L["Sell at"] = "Vender em"
L["Sellers piling in"] = "Vendedores em massa"
L["Sellers withdrawing"] = "Vendedores recuando"
L["Sells for"] = "Vende por"
L["Sells per day (estimate)"] = "Vendas por dia (estimativa)"
L["Sells per day at the sell house"] = "Vendas por dia na casa de venda"
L["Sells/d"] = "Vendas/d"
L["Settings"] = "Configurações"
L["Share full scans with my guild (members running AME)"] =
  "Compartilhar varreduras completas com minha guilda (membros com AME)"
L["Share with guild"] = "Compartilhar com a guilda"
L["Share with trusted players (below)"] = "Compartilhar com jogadores confiáveis (abaixo)"
L["Sharing"] = "Compartilhamento"
L["Sharing settings are on the Sync tab. These options are also in the game's AddOns settings."] =
  "As opções de compartilhamento estão na aba Sincronizar. Estas opções também estão nas configurações de AddOns do jogo."
L["Shift-click to search the auction house"] = "Shift-clique para pesquisar na casa de leilões"
L["Shortage"] = "Escassez"
L["Show AME prices in item tooltips"] = "Mostrar preços do AME nas dicas dos itens"
L["Show minimap button"] = "Mostrar botão no minimapa"
L["Signal"] = "Sinal"
L["Signals and score compare an item with its own history, so they need a week or more of data to mean anything. Items that are cheap AND stable (low volatility) score highest. Supply falling while the price is flat is often a good early sign. None of this is advice - markets can stay weird for a while."] =
  "Sinais e pontuação comparam um item com o próprio histórico, então precisam de uma semana ou mais de dados para significar algo. Itens baratos E estáveis (baixa volatilidade) pontuam mais. Oferta caindo com preço estável costuma ser um bom sinal antecipado. Nada disso é recomendação - mercados podem ficar estranhos por um tempo."
L["Sold / bought"] = "Vendido / comprado"
L["Star items to put them on a watchlist; make more lists with \"+ New list\" in the sidebar (right-click a list to share it with your guild or delete it; guild members' shared lists appear below yours). On an item's page set an alert: below or above a price in gold, or when a buy/sell signal appears. Alerts are checked after every scan and posted in chat with a sound."] =
  'Marque itens com a estrela para colocá-los numa lista de observação; crie mais listas com "+ Nova lista" na barra lateral (clique direito numa lista para compartilhá-la com a guilda ou excluí-la; listas compartilhadas por membros da guilda aparecem abaixo das suas). Na página de um item, defina um alerta: abaixo ou acima de um preço em ouro, ou quando surgir um sinal de compra/venda. Os alertas são verificados após cada varredura e publicados no chat com um som.'
L["Steady demand"] = "Demanda firme"
L["Suppliers"] = "Fornecedores"
L["Supply"] = "Oferta"
L["Swap"] = "Inverter"
L["Sync"] = "Sincronizar"
L["Sync is unavailable: the AceComm library didn't load."] =
  "A sincronização está indisponível: a biblioteca AceComm não carregou."
L["The average daily market price over the chosen period (Settings > Average period, 7 days by default). Compare it with today's market price to see if the item is cheap or expensive right now."] =
  "O preço de mercado diário médio no período escolhido (Configurações > Período da média, 7 dias por padrão). Compare com o preço de mercado de hoje para ver se o item está barato ou caro agora."
L["The cheapest listing at the auction house you buy from - what the first units cost you."] =
  "O anúncio mais barato na casa de leilões onde você compra - quanto custam as primeiras unidades."
L["The market price at the auction house you sell at: what the item typically sells for there."] =
  "O preço de mercado na casa de leilões onde você vende: por quanto o item costuma ser vendido lá."
L["The price chart: market price, lowest listing, 7-day average and supply. Switch to candles for a trading view. Mouse wheel zooms, drag pans, double-click resets. Alt-click any item in the game (bags, chat, the AH) to open it here."] =
  "O gráfico de preços: preço de mercado, menor anúncio, média de 7 dias e oferta. Mude para candles para uma visão de trading. A roda do mouse dá zoom, arrastar move, clique duplo redefine. Alt-clique em qualquer item do jogo (bolsas, chat, a CL) para abri-lo aqui."
L["This market: %d days of history, %d recent scans kept in full"] =
  "Este mercado: %d dias de histórico, %d varreduras recentes mantidas por completo"
L["Tightening"] = "Oferta apertando"
L["Time left"] = "Tempo restante"
L["Top buy signals"] = "Melhores sinais de compra"
L["Total"] = "Total"
L["Trusted"] = "Confiável"
L["Trusted (%d)"] = "Confiáveis (%d)"
L["Trusted players"] = "Jogadores confiáveis"
L["Type %d"] = "Tipo %d"
L["Unblock"] = "Desbloquear"
L["Uncommon+"] = "Incomum+"
L["Unrealized"] = "Não realizado"
L["Unrealized profit"] = "Lucro não realizado"
L["Value"] = "Valor"
L["Volatility"] = "Volatilidade"
L["WAIT"] = "AGUARDAR"
L["Watch"] = "Observar"
L["Watchlists and alerts"] = "Listas de observação e alertas"
L["Weak demand"] = "Demanda fraca"
L["What all your characters hold, valued at your faction's market, with cost and unrealized profit for what you bought on the AH, the Buy/Hold/Sell signal and how long it would take to sell. The ledger lists your AH sales and purchases - recorded from auction mail when you open your mailbox."] =
  "O que todos os seus personagens têm, avaliado no mercado da sua facção, com custo e lucro não realizado do que você comprou na CL, o sinal Comprar/Manter/Vender e quanto tempo levaria para vender. O extrato lista suas vendas e compras na CL - registradas a partir do correio de leilão quando você abre sua caixa de correio."
L["What listing one at the sell house costs up front: a share of the item's vendor price (faction AH 5/20/60% for 2/8/24 hours, goblin AH five times that), at least 1 silver. You get it back when it sells and lose it if it doesn't - so a high deposit on a slow seller is real risk."] =
  "Quanto custa anunciar um na casa de venda, pago na hora: uma parte do preço de venda ao vendedor do item (CL de facção 5/20/60% para 2/8/24 horas, CL Goblin cinco vezes isso), no mínimo 1 prata. Você o recebe de volta quando vende e o perde se não vender - então um depósito alto num item de venda lenta é um risco real."
L["What the item typically sells for right now. From full listing data it's the average of the cheapest 15-30% of the supply on the auction house, which ignores a few cheap or absurd listings. From a browse summary (what many scanners do by default) only the cheapest listing is known, so then it's the lowest price."] =
  "Por quanto o item costuma ser vendido agora. Com dados completos dos anúncios, é a média dos 15-30% mais baratos da oferta na casa de leilões, o que ignora alguns anúncios baratos ou absurdos. Com um resumo de navegação (o que muitos scanners fazem por padrão) só o anúncio mais barato é conhecido, então nesse caso é o menor preço."
L["What to post at so it sells within the listing time - instead of undercutting the cheapest listing by 1c. Buyers take the cheapest listings first, so AME counts the units ahead of you at each price, how fast the item sells, and how often new listings undercut you, and weighs the chance of selling against the deposit you lose if it doesn't. Quick sells within a few hours almost surely, Normal is the best price for the chance, Patient is the highest price that still sells about half the time. It learns every item's pattern from your scans (busy hours, weekdays, how hard sellers compete) and from your own posts: if items keep expiring at its prices it gets more careful for that item. With little data it borrows from similar items; the bars show how much it knows."] =
  "Por quanto leiloar para vender dentro da duração do leilão, em vez de baixar 1 cobre do leilão mais barato. Os compradores levam primeiro os leilões mais baratos, então o AME conta as unidades à sua frente em cada preço, a rapidez com que o item vende e a frequência com que novos leilões ficam abaixo do seu preço, e pesa a chance de vender contra o depósito que você perde se não vender. Rápido vende quase com certeza em poucas horas, Normal é o melhor preço para a chance, Paciente é o preço mais alto que ainda vende cerca de metade das vezes. O AME aprende o padrão de cada item com suas varreduras (horários de pico, dias da semana, quão forte é a concorrência entre vendedores) e com seus próprios leilões: se itens expiram com frequência nos preços dele, ele fica mais cauteloso com aquele item. Com poucos dados, ele se baseia em itens semelhantes; as barras mostram quanto ele sabe."
L["What you paid per unit for the units you bought on the auction house (oldest purchases are sold first). Items you looted or crafted have no cost."] =
  "Quanto você pagou por unidade pelas unidades que comprou na casa de leilões (as compras mais antigas são vendidas primeiro). Itens saqueados ou criados não têm custo."
L["When"] = "Quando"
L["Where the data comes from"] = "De onde vêm os dados"
L["Window colours"] = "Cores da janela"
L["You haven't blocked anyone."] = "Você não bloqueou ninguém."
L["You'd receive (after the cut)"] = "Você receberia (após a taxa)"
L["Your active auctions on all characters, as of the last time each opened the auction house."] =
  "Seus leilões ativos em todos os personagens, desde a última vez que cada um abriu a casa de leilões."
L["Your alts on this Battle.net account already share everything: AME's history is saved account-wide. Trust players to swap scans with friends, or with your own characters on other accounts. Only your market and auction house are shared, and scans that disagree wildly with your prices are rejected."] =
  "Seus alts nesta conta Battle.net já compartilham tudo: o histórico do AME é salvo para a conta inteira. Confie em jogadores para trocar varreduras com amigos ou com seus próprios personagens em outras contas. Só o seu mercado e a sua casa de leilões são compartilhados, e varreduras que divergem demais dos seus preços são rejeitadas."
L["Your auction mail doesn't name the other player on this client (the auction house keeps them anonymous), so there's no one to list."] =
  "Seu correio de leilão não nomeia o outro jogador neste cliente (a casa de leilões o mantém anônimo), então não há ninguém para listar."
L["a list needs a name"] = "a lista precisa de um nome"
L["a list with that name already exists"] = "já existe uma lista com esse nome"
L["a week+"] = "uma semana+"
L["above g"] = "acima de g"
L["announced %d, served %d, received %d, rejected %d"] = "anunciadas %d, servidas %d, recebidas %d, rejeitadas %d"
L["auctionator history import"] = "importação de histórico do Auctionator"
L["average period"] = "período da média"
L["awaiting mail"] = "aguardando correio"
L["backfill"] = "preenchimento de histórico"
L["below g"] = "abaixo de g"
L["blocked"] = "bloqueado"
L["blocked %s"] = "%s bloqueado"
L["bought"] = "comprado"
L["chart library + window"] = "biblioteca de gráficos + janela"
L["codec+compress 6.4k items"] = "codec+compressão 6.4k itens"
L["could not load %s: %s"] = "não foi possível carregar %s: %s"
L["could not load history addon"] = "não foi possível carregar o addon de histórico"
L["couldn't start an auction house search for %s"] =
  "não foi possível iniciar uma pesquisa na casa de leilões para %s"
L["data"] = "dados"
L["deposit %s"] = "depósito %s"
L["done %s"] = "concluído %s"
L["down  (wick = cheapest)"] = "queda  (pavio = mais barato)"
L["dropped to %s (alert at %s)"] = "caiu para %s (alerta em %s)"
L["encode %.0f ms, compress %.0f ms, unpack+decode %.0f ms, %d KB -> %d KB"] =
  "codificar %.0f ms, comprimir %.0f ms, desempacotar+decodificar %.0f ms, %d KB -> %d KB"
L["ended?"] = "encerrado?"
L["enter a character name"] = "digite um nome de personagem"
L["guild sync"] = "sincronização da guilda"
L["guild sync: %s, announced %d, served %d, received %d, rejected %d"] =
  "sincronização da guilda: %s, anunciadas %d, servidas %d, recebidas %d, rejeitadas %d"
L["history addon"] = "addon de histórico"
L["history import from Auctionator failed: %s"] = "falha ao importar histórico do Auctionator: %s"
L["history import from Auctionator is only done at your faction's auction house (its data mixes all houses)."] =
  "a importação de histórico do Auctionator só é feita na casa de leilões da sua facção (os dados dele misturam todas as casas)."
L["history lookup (cold)"] = "consulta de histórico (a frio)"
L["history: %d raw scans, %d days, %.0f KB"] = "histórico: %d varreduras brutas, %d dias, %.0f KB"
L["imported %d days of price history from Auctionator into %s"] =
  "%d dias de histórico de preços importados do Auctionator para %s"
L["item %d: %d points in %.1f ms"] = "item %d: %d pontos em %.1f ms"
L["item from latest scan has no daily points"] = "item da última varredura não tem pontos diários"
L["item not loaded yet - try again in a moment"] = "item ainda não carregado - tente de novo em instantes"
L["just now"] = "agora mesmo"
L["last full scan"] = "última varredura completa"
L["last full scan: %d items, %s ago"] = "última varredura completa: %d itens, há %s"
L["last seen %s"] = "visto pela última vez %s"
L["libraries"] = "bibliotecas"
L["loaded in %s ms, %d shard(s), %.0f KB of daily history"] =
  "carregado em %s ms, %d fragmento(s), %.0f KB de histórico diário"
L["loading history..."] = "carregando histórico..."
L["loading item names %d/%d"] = "carregando nomes de itens %d/%d"
L["lowest"] = "menor"
L["margin %"] = "margem %"
L["market"] = "mercado"
L["market index"] = "índice de mercado"
L["market index failed:"] = "falha no índice de mercado:"
L["max g"] = "máx. g"
L["min g"] = "mín. g"
L["never"] = "nunca"
L["no full scan recorded yet: open the AH and run a full scan (your scanning addon's or the game's)"] =
  "nenhuma varredura completa registrada ainda: abra a CL e faça uma varredura completa (a do seu addon de varredura ou a do jogo)"
L["no history for %s in %s"] = "sem histórico para %s em %s"
L["no scans in this shard yet"] = "nenhuma varredura neste fragmento ainda"
L["none"] = "nenhum"
L["none yet: open the AH and run a full scan, then rerun /ame selftest"] =
  "nenhuma ainda: abra a CL e faça uma varredura completa, depois execute /ame selftest de novo"
L["not in a guild"] = "não está em uma guilda"
L["not loaded"] = "não carregado"
L["nothing imported here (only with Auctionator data, at your faction's auction house)"] =
  "nada importado aqui (só com dados do Auctionator, na casa de leilões da sua facção)"
L["off"] = "desativado"
L["on"] = "ativado"
L["on buy/sell signal"] = "com sinal de compra/venda"
L["on, but you're not in a guild"] = "ativado, mas você não está em uma guilda"
L["open the auction house first"] = "abra a casa de leilões primeiro"
L["profit g"] = "lucro g"
L["reading full scan (%d listings) in the background..."] =
  "lendo varredura completa (%d anúncios) em segundo plano..."
L["received a full scan from %s via sync (%d items, %s)"] =
  "varredura completa recebida de %s via sincronização (%d itens, %s)"
L["recorded full scan: %d items from %d listings (%s)"] = "varredura completa registrada: %d itens de %d anúncios (%s)"
L["rose to %s (alert at %s)"] = "subiu para %s (alerta em %s)"
L["round trip mismatch"] = "divergência na ida e volta"
L["scan pipeline: %d requests, %d events (%d since last request), read %s, aborted %d; ingest requested=%s reading=%s"] =
  "pipeline de varredura: %d solicitações, %d eventos (%d desde a última solicitação), leitura %s, abortadas %d; ingestão requested=%s reading=%s"
L["scan read failed:"] = "falha na leitura da varredura:"
L["score"] = "pontuação"
L["score %+d"] = "pontuação %+d"
L["search"] = "pesquisar"
L["selftest finished:\n%s\n\nReload the UI now to save the results?"] =
  "autoteste concluído:\n%s\n\nRecarregar a IU agora para salvar os resultados?"
L["selftest starting (this may pause the game for a moment)"] =
  "iniciando autoteste (o jogo pode travar por um instante)"
L["selftest: %d passed, %d warnings, %d failed. Reload to save the results (/reload)."] =
  "autoteste: %d aprovados, %d avisos, %d falhas. Recarregue para salvar os resultados (/reload)."
L["shard"] = "fragmento"
L["shared"] = "compartilhada"
L["sharing"] = "compartilhamento"
L["signal"] = "sinal"
L["sold"] = "vendido"
L["storing %s scan failed:"] = "falha ao armazenar varredura %s:"
L["supply"] = "oferta"
L["the AH closed before AME finished reading the full scan; it wasn't recorded."] =
  "a CL fechou antes de o AME terminar de ler a varredura completa; ela não foi registrada."
L["today"] = "hoje"
L["turned off in settings"] = "desativado nas configurações"
L["unknown command, try /ame help"] = "comando desconhecido, tente /ame help"
L["unlikely to sell soon: consider holding"] = "pouco provável vender logo: considere manter"
L["up"] = "alta"
L["usage: /ame item <item link or itemID>"] = "uso: /ame item <link do item ou itemID>"
L["volatility"] = "volatilidade"
L["waiting for them to approve"] = "aguardando a aprovação dele"
L["wants to share, %s"] = "quer compartilhar, %s"
L["well below its usual price"] = "bem abaixo do preço habitual"
L["wheel: zoom, drag: pan, double-click: reset"] = "roda: zoom, arrastar: mover, clique duplo: redefinir"
L["whisper"] = "sussurro"
L["window created, market tab rendered"] = "janela criada, aba de mercado renderizada"
L["yesterday"] = "ontem"
L["you're at the buy AH: Search (or Shift-click a row) to buy"] =
  "você está na CL de compra: Pesquisar (ou Shift-clique numa linha) para comprar"
L["~%d days"] = "~%d dias"
L["~%dh"] = "~%d h"
