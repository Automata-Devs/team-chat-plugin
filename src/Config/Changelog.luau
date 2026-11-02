--!
-- Changelog
-- What's new, Minecraft-style: MAIN VERSIONS (1.0.0, 2.0.0, ...) each hold
-- their SUBVERSIONS (1.13.1, 1.12.4, ...), newest first. A version x.y.z
-- belongs to main version x.0.0. Shown in the "What's New" tab: the main
-- versions as tabs, their subversions under them. It pops up once after an
-- update that has notes.
--
-- To add an update: bump the plugin's Version attribute, then in its main
-- version's `updates`:
--   - same day and theme as the top update: set its version to the new one
--     and add your changes to its list;
--   - otherwise add a new update at the TOP of `updates`:
--
--   {
--       version = "1.14.0",             -- must match the Version attribute exactly
--       date = "02/11/2026",            -- DD/MM/YYYY
--       title = "Short headline",       -- optional
--       changes = {
--           { type = "added",   text = "A new feature." },
--           { type = "changed", text = "Something that works differently." },
--           { type = "fixed",   text = "A bug that was fixed." },
--           { type = "removed", text = "Something that is gone." },
--       },
--   },
--
-- A new main version (2.0.0) is a new block at the TOP of the returned list,
-- with its own title, date and `updates`.
--
-- Change types follow Keep a Changelog (https://keepachangelog.com).
-- Only big updates get an entry; small version bumps don't, and What's New
-- then keeps showing the last big update.
--!

-- UNRELEASED: every change since the last published entry (bugs, fixes,
-- tweaks), newest first, tagged with the version it went into. Not shown in
-- What's New. When something big ships, move these lines into a new entry at
-- the top of the list below and empty this list.
local unreleased = {}
local _ = unreleased

return {
	{
		version = "1.0.0", -- main version: every 1.x.x update is listed under it
		date = "31/10/2026",
		title = "Team Chat 1",
		updates = {
			{
				version = "1.20.0",
				date = "02/11/2026",
				title = {
					en = "Formatting",
					nl = "Opmaak",
					de = "Formatierung",
					es = "Formato",
					fr = "Mise en forme",
					pt = "Formatação",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "Markdown like Discord: **bold**, *italic*, __underline__, ~~strikethrough~~, `code`, ```code blocks```, ||spoilers||, # headers, -# subtext, > quotes, - lists and [masked links](https://…).",
							nl = "Markdown zoals Discord: **vet**, *cursief*, __onderstreept__, ~~doorgestreept~~, `code`, ```codeblokken```, ||spoilers||, # koppen, -# kleine tekst, > citaten, - lijsten en [verborgen links](https://…).",
							de = "Markdown wie bei Discord: **fett**, *kursiv*, __unterstrichen__, ~~durchgestrichen~~, `Code`, ```Codeblöcke```, ||Spoiler||, # Überschriften, -# kleiner Text, > Zitate, - Listen und [maskierte Links](https://…).",
							es = "Markdown como en Discord: **negrita**, *cursiva*, __subrayado__, ~~tachado~~, `código`, ```bloques de código```, ||spoilers||, # títulos, -# texto pequeño, > citas, - listas y [enlaces con texto](https://…).",
							fr = "Markdown comme sur Discord : **gras**, *italique*, __souligné__, ~~barré~~, `code`, ```blocs de code```, ||spoilers||, # titres, -# petit texte, > citations, - listes et [liens masqués](https://…).",
							pt = "Markdown como no Discord: **negrito**, *itálico*, __sublinhado__, ~~tachado~~, `código`, ```blocos de código```, ||spoilers||, # títulos, -# texto pequeno, > citações, - listas e [links com texto](https://…).",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Mentions of your display name count, a reply to your message glows gold and notifies you like a mention, and @mentions show in blue in reply lines.",
							nl = "Vermeldingen van je weergavenaam tellen mee, een antwoord op je bericht licht goud op en geeft een melding zoals een vermelding, en @vermeldingen zijn blauw in antwoordregels.",
							de = "Erwähnungen deines Anzeigenamens zählen, eine Antwort auf deine Nachricht leuchtet golden und benachrichtigt dich wie eine Erwähnung, und @Erwähnungen sind in Antwortzeilen blau.",
							es = "Las menciones de tu nombre visible cuentan, una respuesta a tu mensaje brilla en dorado y te avisa como una mención, y las @menciones se ven en azul en las líneas de respuesta.",
							fr = "Les mentions de ton nom d'affichage comptent, une réponse à ton message brille en doré et te notifie comme une mention, et les @mentions sont en bleu dans les lignes de réponse.",
							pt = "Menções ao seu nome de exibição contam, uma resposta à sua mensagem brilha em dourado e notifica você como uma menção, e as @menções aparecem em azul nas linhas de resposta.",
						},
					},
				},
			},
			{
				version = "1.19.0",
				date = "02/11/2026",
				title = {
					en = "Team Chat bot",
					nl = "Team Chat-bot",
					de = "Team-Chat-Bot",
					es = "Bot de Team Chat",
					fr = "Bot Team Chat",
					pt = "Bot do Team Chat",
				},
				changes = {
					{
						type = "added",
						text = {
							en = 'Team Chat is a verified bot. Its replies are either just for you ("Only you can see this", with Dismiss message) or posted for everyone under "<name> used /command", like moderation actions, /roll and /coinflip.',
							nl = 'Team Chat is een geverifieerde bot. Zijn antwoorden zijn alleen voor jou ("Alleen jij ziet dit", met Bericht verbergen) of voor iedereen onder "<naam> gebruikte /commando", zoals moderatie, /roll en /coinflip.',
							de = 'Team Chat ist ein verifizierter Bot. Seine Antworten sind entweder nur für dich ("Nur du siehst das", mit Nachricht ausblenden) oder für alle unter "<Name> hat /Befehl verwendet", etwa Moderation, /roll und /coinflip.',
							es = 'Team Chat es un bot verificado. Sus respuestas son solo para ti ("Solo tú puedes ver esto", con Descartar mensaje) o para todos bajo "<nombre> usó /comando", como la moderación, /roll y /coinflip.',
							fr = "Team Chat est un bot vérifié. Ses réponses sont soit pour toi seul (« Toi seul peux voir ceci », avec Masquer le message), soit pour tout le monde sous « <nom> a utilisé /commande », comme la modération, /roll et /coinflip.",
							pt = 'O Team Chat é um bot verificado. As respostas dele são só para você ("Só você pode ver isto", com Dispensar mensagem) ou para todos sob "<nome> usou /comando", como a moderação, /roll e /coinflip.',
						},
					},
					{
						type = "added",
						text = {
							en = "More commands reply with cards: moderation (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge and the full /help list.",
							nl = "Meer commando's antwoorden met kaarten: moderatie (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge en de hele /help-lijst.",
							de = "Mehr Befehle antworten mit Karten: Moderation (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge und die ganze /help-Liste.",
							es = "Más comandos responden con tarjetas: moderación (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge y la lista completa de /help.",
							fr = "Plus de commandes répondent avec des cartes : modération (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge et la liste complète de /help.",
							pt = "Mais comandos respondem com cartões: moderação (ban, kick, mute, warn, …), /who, /listblacklist, /listwhitelist, /restore, /backup, /slowmode, /purge e a lista completa do /help.",
						},
					},
				},
			},
			{
				version = "1.18.0",
				date = "02/11/2026",
				title = {
					en = "Command cards",
					nl = "Commandokaarten",
					de = "Befehlskarten",
					es = "Tarjetas de comandos",
					fr = "Cartes de commandes",
					pt = "Cartões de comandos",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "Commands reply with neat cards instead of a pile of lines: /whois (with their avatar), /stats, /serverstatus, /listusers, /warnings and /help <command>.",
							nl = "Commando's antwoorden met nette kaarten in plaats van een stapel regels: /whois (met hun avatar), /stats, /serverstatus, /listusers, /warnings en /help <commando>.",
							de = "Befehle antworten mit übersichtlichen Karten statt vieler Zeilen: /whois (mit Avatar), /stats, /serverstatus, /listusers, /warnings und /help <Befehl>.",
							es = "Los comandos responden con tarjetas ordenadas en lugar de un montón de líneas: /whois (con su avatar), /stats, /serverstatus, /listusers, /warnings y /help <comando>.",
							fr = "Les commandes répondent avec des cartes claires au lieu d'une pile de lignes : /whois (avec l'avatar), /stats, /serverstatus, /listusers, /warnings et /help <commande>.",
							pt = "Os comandos respondem com cartões organizados em vez de várias linhas: /whois (com o avatar), /stats, /serverstatus, /listusers, /warnings e /help <comando>.",
						},
					},
					{
						type = "changed",
						text = {
							en = 'The plugin\'s own messages come from Team Chat, verified, with an APP tag, instead of "System".',
							nl = 'De eigen berichten van de plugin komen van Team Chat, geverifieerd, met een APP-label, in plaats van "System".',
							de = 'Die eigenen Nachrichten des Plugins kommen von Team Chat, verifiziert und mit APP-Kennzeichnung, statt von "System".',
							es = 'Los mensajes del propio plugin vienen de Team Chat, verificado y con la etiqueta APP, en lugar de "System".',
							fr = "Les messages du plugin viennent de Team Chat, vérifié, avec une étiquette APP, au lieu de « System ».",
							pt = 'As mensagens do próprio plugin vêm do Team Chat, verificado, com a etiqueta APP, em vez de "System".',
						},
					},
					{
						type = "changed",
						text = {
							en = "@mentions have rounded corners, and show highlighted in the message box while you type them.",
							nl = "@vermeldingen hebben ronde hoeken en worden al gemarkeerd in het berichtvak terwijl je ze typt.",
							de = "@Erwähnungen haben runde Ecken und werden schon beim Tippen im Nachrichtenfeld hervorgehoben.",
							es = "Las @menciones tienen esquinas redondeadas y se resaltan en el cuadro de mensaje mientras las escribes.",
							fr = "Les @mentions ont des coins arrondis et sont surlignées dans la zone de message pendant que tu les tapes.",
							pt = "As @menções têm cantos arredondados e ficam destacadas na caixa de mensagem enquanto você digita.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "The unread badge is a solid red circle again, a little bigger.",
							nl = "De badge voor ongelezen berichten is weer een volle rode cirkel, iets groter.",
							de = "Das Ungelesen-Abzeichen ist wieder ein voller roter Kreis, etwas größer.",
							es = "El contador de no leídos vuelve a ser un círculo rojo sólido, un poco más grande.",
							fr = "Le badge des non-lus est de nouveau un cercle rouge plein, un peu plus grand.",
							pt = "O contador de não lidas voltou a ser um círculo vermelho sólido, um pouco maior.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "No more errors in Output when you drag something that isn't a chat attachment (like an Explorer item) over the chat.",
							nl = "Geen fouten meer in Output als je iets dat geen chatbijlage is (zoals een item uit de Explorer) over de chat sleept.",
							de = "Keine Fehler mehr in der Ausgabe, wenn du etwas, das kein Chat-Anhang ist (z. B. ein Explorer-Element), über den Chat ziehst.",
							es = "Ya no hay errores en Output al arrastrar sobre el chat algo que no es un adjunto (como un elemento del Explorer).",
							fr = "Plus d'erreurs dans Output quand tu fais glisser sur la discussion quelque chose qui n'est pas une pièce jointe (comme un élément de l'Explorer).",
							pt = "Sem mais erros no Output ao arrastar sobre o chat algo que não é um anexo (como um item do Explorer).",
						},
					},
				},
			},
			{
				version = "1.17.0",
				date = "02/11/2026",
				title = {
					en = "Mentions",
					nl = "Vermeldingen",
					de = "Erwähnungen",
					es = "Menciones",
					fr = "Mentions",
					pt = "Menções",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "@mentions: type @ in the message box to pick someone from the Members list (people here and your DM contacts), or @everyone. Tab or click puts them in.",
							nl = "@vermeldingen: typ @ in het berichtvak om iemand uit de lijst Leden te kiezen (mensen hier en je DM-contacten), of @everyone. Tab of klik zet de naam erin.",
							de = "@Erwähnungen: Tippe @ ins Nachrichtenfeld, um jemanden aus der Mitgliederliste zu wählen (Leute hier und deine DM-Kontakte), oder @everyone. Tab oder Klick fügt den Namen ein.",
							es = "@menciones: escribe @ en el cuadro de mensaje para elegir a alguien de la lista de Miembros (gente aquí y tus contactos de MD), o @everyone. Tab o clic lo añade.",
							fr = "@mentions : tape @ dans la zone de message pour choisir quelqu'un dans la liste des Membres (les personnes ici et tes contacts MP), ou @everyone. Tab ou clic l'insère.",
							pt = "@menções: digite @ na caixa de mensagem para escolher alguém da lista de Membros (pessoas aqui e seus contatos de DM), ou @everyone. Tab ou clique insere o nome.",
						},
					},
					{
						type = "added",
						text = {
							en = "Mentions are highlighted in messages, and a message that mentions you (or @everyone) glows gold with a bar on the left. It also notifies you, even with Notifications set to DMs only.",
							nl = "Vermeldingen worden gemarkeerd in berichten, en een bericht dat jou (of @everyone) noemt licht goud op met een balk links. Je krijgt er ook een melding van, zelfs met Meldingen op Alleen DM's.",
							de = "Erwähnungen werden in Nachrichten hervorgehoben, und eine Nachricht, die dich (oder @everyone) erwähnt, leuchtet golden mit einem Balken links. Sie benachrichtigt dich auch, selbst wenn Benachrichtigungen auf Nur DMs steht.",
							es = "Las menciones se resaltan en los mensajes, y un mensaje que te menciona (o @everyone) brilla en dorado con una barra a la izquierda. También te avisa, aunque Notificaciones esté en Solo MD.",
							fr = "Les mentions sont surlignées dans les messages, et un message qui te mentionne (ou @everyone) brille en doré avec une barre à gauche. Il te notifie aussi, même avec Notifications sur MP seulement.",
							pt = "As menções ficam destacadas nas mensagens, e uma mensagem que menciona você (ou @everyone) brilha em dourado com uma barra à esquerda. Ela também notifica você, mesmo com Notificações em Só DMs.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "The reply line is an even, smooth curve that stops just above the avatar and follows the theme.",
							nl = "De antwoordlijn is een gelijkmatige, vloeiende boog die net boven de avatar stopt en het thema volgt.",
							de = "Die Antwortlinie ist eine gleichmäßige, glatte Kurve, die knapp über dem Avatar endet und dem Design folgt.",
							es = "La línea de respuesta es una curva uniforme y suave que termina justo encima del avatar y sigue el tema.",
							fr = "La ligne de réponse est une courbe régulière et lisse qui s'arrête juste au-dessus de l'avatar et suit le thème.",
							pt = "A linha de resposta é uma curva uniforme e suave que termina logo acima do avatar e segue o tema.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "The small avatar in replies has the plain avatar background instead of the author's name colour, and is a little see-through.",
							nl = "De kleine avatar in antwoorden heeft de gewone avatarachtergrond in plaats van de naamkleur van de auteur, en is een beetje doorzichtig.",
							de = "Der kleine Avatar in Antworten hat den normalen Avatar-Hintergrund statt der Namensfarbe und ist leicht durchsichtig.",
							es = "El avatar pequeño de las respuestas tiene el fondo normal de avatar en lugar del color del nombre del autor, y es un poco transparente.",
							fr = "Le petit avatar des réponses a le fond d'avatar normal au lieu de la couleur du nom de l'auteur, et il est un peu transparent.",
							pt = "O avatar pequeno das respostas tem o fundo normal de avatar em vez da cor do nome do autor, e é um pouco transparente.",
						},
					},
				},
			},
			{
				version = "1.16.1",
				date = "02/11/2026",
				title = {
					en = "Chat upgrades",
					nl = "Chat-verbeteringen",
					de = "Chat-Verbesserungen",
					es = "Mejoras del chat",
					fr = "Améliorations de la discussion",
					pt = "Melhorias no chat",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "Unread messages: a red NEW line above the first one when you open a conversation, the badge pops when more arrive, and the total shows in the window's title.",
							nl = "Ongelezen berichten: een rode NIEUW-lijn boven het eerste als je een gesprek opent, de badge springt op als er meer binnenkomen, en het totaal staat in de titel van het venster.",
							de = "Ungelesene Nachrichten: eine rote NEU-Linie über der ersten, wenn du ein Gespräch öffnest, das Abzeichen hüpft bei neuen, und die Gesamtzahl steht im Fenstertitel.",
							es = "Mensajes sin leer: una línea roja NUEVO sobre el primero al abrir una conversación, el contador salta cuando llegan más, y el total aparece en el título de la ventana.",
							fr = "Messages non lus : une ligne rouge NOUVEAU au-dessus du premier quand tu ouvres une conversation, le compteur rebondit quand d'autres arrivent, et le total s'affiche dans le titre de la fenêtre.",
							pt = "Mensagens não lidas: uma linha vermelha NOVO acima da primeira ao abrir uma conversa, o contador pula quando chegam mais, e o total aparece no título da janela.",
						},
					},
					{
						type = "added",
						text = {
							en = "A note under the header when the place isn't in Team Create: only you can see the chat there, and Collaborate turns sharing on.",
							nl = "Een melding onder de kop als de place niet in Team Create staat: alleen jij ziet de chat daar, en Collaborate zet delen aan.",
							de = "Ein Hinweis unter der Kopfzeile, wenn der Ort nicht in Team Create ist: Dort siehst nur du den Chat, und Collaborate schaltet das Teilen ein.",
							es = "Un aviso bajo el encabezado cuando el lugar no está en Team Create: ahí solo tú ves el chat, y Collaborate activa el uso compartido.",
							fr = "Une note sous l'en-tête quand l'emplacement n'est pas dans Team Create : toi seul y vois la discussion, et Collaborate active le partage.",
							pt = "Um aviso abaixo do cabeçalho quando o lugar não está no Team Create: só você vê o chat ali, e o Collaborate ativa o compartilhamento.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "The typing indicator works in DMs, and only shows who's typing in the conversation you have open.",
							nl = "De typindicator werkt in DM's en toont alleen wie er typt in het gesprek dat je open hebt.",
							de = "Die Tippanzeige funktioniert in DMs und zeigt nur, wer im geöffneten Gespräch tippt.",
							es = "El indicador de escritura funciona en los MD y solo muestra quién escribe en la conversación que tienes abierta.",
							fr = "L'indicateur de saisie fonctionne dans les MP et ne montre que qui écrit dans la conversation ouverte.",
							pt = "O indicador de digitação funciona nas DMs e só mostra quem está digitando na conversa aberta.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "You can only delete your own messages; Delete no longer shows on other people's.",
							nl = "Je kunt alleen je eigen berichten verwijderen; Verwijderen staat niet meer bij die van anderen.",
							de = "Du kannst nur noch deine eigenen Nachrichten löschen; Löschen erscheint nicht mehr bei denen anderer.",
							es = "Solo puedes borrar tus propios mensajes; Eliminar ya no aparece en los de otras personas.",
							fr = "Tu ne peux supprimer que tes propres messages ; Supprimer n'apparaît plus sur ceux des autres.",
							pt = "Você só pode apagar suas próprias mensagens; Excluir não aparece mais nas dos outros.",
						},
					},
				},
			},
			{
				version = "1.15.1",
				date = "02/11/2026",
				title = {
					en = "Languages",
					nl = "Talen",
					de = "Sprachen",
					es = "Idiomas",
					fr = "Langues",
					pt = "Idiomas",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "Settings > Language: English, Nederlands, Deutsch, Español, Français and Português. Auto follows Studio's language, and switching changes the plugin right away.",
							nl = "Instellingen > Taal: English, Nederlands, Deutsch, Español, Français en Português. Automatisch volgt de taal van Studio, en wisselen verandert de plugin meteen.",
							de = "Einstellungen > Sprache: English, Nederlands, Deutsch, Español, Français und Português. Automatisch folgt der Sprache von Studio, und ein Wechsel ändert das Plugin sofort.",
							es = "Configuración > Idioma: English, Nederlands, Deutsch, Español, Français y Português. Automático sigue el idioma de Studio, y al cambiarlo el plugin cambia al instante.",
							fr = "Paramètres > Langue : English, Nederlands, Deutsch, Español, Français et Português. Automatique suit la langue de Studio, et changer de langue modifie le plugin tout de suite.",
							pt = "Configurações > Idioma: English, Nederlands, Deutsch, Español, Français e Português. Automático segue o idioma do Studio, e trocar muda o plugin na hora.",
						},
					},
					{
						type = "added",
						text = {
							en = "The rest of the plugin speaks your language too: Badges, Checkout, About, New message, Create a Poll, What's New, notifications, and command help and replies.",
							nl = "De rest van de plugin spreekt nu ook jouw taal: Badges, Afrekenen, Over, Nieuw bericht, Peiling maken, Wat is er nieuw, meldingen, en de hulp en antwoorden van commando's.",
							de = "Auch der Rest des Plugins spricht jetzt deine Sprache: Abzeichen, Kasse, Über, Neue Nachricht, Umfrage erstellen, Neuigkeiten, Benachrichtigungen sowie Hilfe und Antworten der Befehle.",
							es = "El resto del plugin también habla tu idioma: Insignias, Pago, Acerca de, Nuevo mensaje, Crear encuesta, Novedades, notificaciones, y la ayuda y respuestas de los comandos.",
							fr = "Le reste du plugin parle aussi ta langue : Badges, Paiement, À propos, Nouveau message, Créer un sondage, Nouveautés, notifications, ainsi que l'aide et les réponses des commandes.",
							pt = "O resto do plugin também fala o seu idioma: Emblemas, Pagamento, Sobre, Nova mensagem, Criar enquete, Novidades, notificações, e a ajuda e as respostas dos comandos.",
						},
					},
					{
						type = "added",
						text = {
							en = "What's New notes can be translated; the newest updates are, and older notes stay in English.",
							nl = "Notities in Wat is er nieuw kunnen vertaald worden; de nieuwste updates zijn dat, oudere notities blijven Engels.",
							de = "Notizen in Neuigkeiten können übersetzt werden; die neuesten Updates sind es, ältere Notizen bleiben auf Englisch.",
							es = "Las notas de Novedades se pueden traducir; las de las actualizaciones más nuevas lo están, y las antiguas siguen en inglés.",
							fr = "Les notes de Nouveautés peuvent être traduites ; celles des dernières mises à jour le sont, les plus anciennes restent en anglais.",
							pt = "As notas de Novidades podem ser traduzidas; as das atualizações mais novas estão, e as antigas continuam em inglês.",
						},
					},
				},
			},
			{
				version = "1.14.0",
				date = "02/11/2026",
				title = {
					en = "A new What's New",
					nl = "Een nieuw Wat is er nieuw",
					de = "Ein neues Neuigkeiten",
					es = "Un nuevo Novedades",
					fr = "Un nouveau Nouveautés",
					pt = "Um novo Novidades",
				},
				changes = {
					{
						type = "changed",
						text = {
							en = "What's New works like Minecraft: big versions (1.0) are the tabs, and every update in them (1.14.0, 1.13.1, ...) is a card you can fold open.",
							nl = "Wat is er nieuw werkt nu zoals Minecraft: grote versies (1.0) zijn de tabbladen, en elke update daarin (1.14.0, 1.13.1, ...) is een kaart die je kunt openklappen.",
							de = "Neuigkeiten funktioniert wie bei Minecraft: Große Versionen (1.0) sind die Tabs, und jedes Update darin (1.14.0, 1.13.1, ...) ist eine Karte zum Aufklappen.",
							es = "Novedades funciona como Minecraft: las versiones grandes (1.0) son las pestañas, y cada actualización dentro (1.14.0, 1.13.1, ...) es una tarjeta que puedes desplegar.",
							fr = "Nouveautés fonctionne comme Minecraft : les grandes versions (1.0) sont les onglets, et chaque mise à jour (1.14.0, 1.13.1, ...) est une carte que tu peux déplier.",
							pt = "Novidades funciona como no Minecraft: as versões grandes (1.0) são as abas, e cada atualização nelas (1.14.0, 1.13.1, ...) é um cartão que você pode abrir.",
						},
					},
				},
			},
			{
				version = "1.13.1",
				date = "01/11/2026",
				title = {
					en = "Badges on sale",
					nl = "Badges te koop",
					de = "Abzeichen im Verkauf",
					es = "Insignias a la venta",
					fr = "Badges en vente",
					pt = "Emblemas à venda",
				},
				changes = {
					{
						type = "added",
						text = {
							en = "Badges are on sale: Premium, Diamond, Star and Supporter. Buy opens the badge on Roblox.com, and it shows up next to your name once you've bought it.",
							nl = "Badges zijn te koop: Premium, Diamant, Ster en Supporter. Kopen opent de badge op Roblox.com, en hij verschijnt naast je naam zodra je hem hebt gekocht.",
							de = "Abzeichen sind im Verkauf: Premium, Diamant, Stern und Unterstützer. Kaufen öffnet das Abzeichen auf Roblox.com, und es erscheint neben deinem Namen, sobald du es gekauft hast.",
							es = "Las insignias están a la venta: Premium, Diamante, Estrella y Colaborador. Comprar abre la insignia en Roblox.com, y aparece junto a tu nombre en cuanto la compras.",
							fr = "Les badges sont en vente : Premium, Diamant, Étoile et Soutien. Acheter ouvre le badge sur Roblox.com, et il apparaît à côté de ton nom une fois acheté.",
							pt = "Os emblemas estão à venda: Premium, Diamante, Estrela e Apoiador. Comprar abre o emblema no Roblox.com, e ele aparece ao lado do seu nome assim que você compra.",
						},
					},
				},
			},
			{
				version = "1.12.4",
				date = "01/11/2026",
				title = {
					en = "New Settings",
					nl = "Nieuwe instellingen",
					de = "Neue Einstellungen",
					es = "Nueva configuración",
					fr = "Nouveaux paramètres",
					pt = "Novas configurações",
				},
				changes = {
					{
						type = "changed",
						text = {
							en = "Settings got a new look: each setting is a card with its name, a toggle, slider or dropdown on the right, and a short description, grouped into Appearance, Chat and Notifications.",
							nl = "Instellingen hebben een nieuw uiterlijk: elke instelling is een kaart met de naam, rechts een schakelaar, schuifregelaar of keuzelijst, en een korte uitleg, gegroepeerd in Uiterlijk, Chat en Meldingen.",
							de = "Die Einstellungen sehen neu aus: Jede Einstellung ist eine Karte mit Namen, rechts einem Schalter, Schieberegler oder Auswahlmenü und einer kurzen Beschreibung, gruppiert in Darstellung, Chat und Benachrichtigungen.",
							es = "La configuración tiene un nuevo aspecto: cada ajuste es una tarjeta con su nombre, un interruptor, control deslizante o desplegable a la derecha, y una breve descripción, agrupados en Apariencia, Chat y Notificaciones.",
							fr = "Les paramètres ont un nouveau look : chaque paramètre est une carte avec son nom, un interrupteur, un curseur ou une liste à droite, et une courte description, regroupés en Apparence, Discussion et Notifications.",
							pt = "As configurações ganharam um visual novo: cada opção é um cartão com o nome, um botão, controle deslizante ou menu à direita, e uma breve descrição, agrupados em Aparência, Chat e Notificações.",
						},
					},
					{
						type = "added",
						text = {
							en = "Search settings: type to find a setting by its name or description.",
							nl = "Instellingen zoeken: typ om een instelling te vinden op naam of uitleg.",
							de = "Einstellungen durchsuchen: Tippe, um eine Einstellung nach Name oder Beschreibung zu finden.",
							es = "Buscar ajustes: escribe para encontrar un ajuste por su nombre o descripción.",
							fr = "Recherche dans les paramètres : tape pour trouver un paramètre par son nom ou sa description.",
							pt = "Pesquisar configurações: digite para encontrar uma opção pelo nome ou pela descrição.",
						},
					},
					{
						type = "added",
						text = {
							en = "Message Text Size is now a slider (11-20px), and Notification Duration (2-10 seconds) is new.",
							nl = "Tekstgrootte van berichten is nu een schuifregelaar (11-20px), en Meldingsduur (2-10 seconden) is nieuw.",
							de = "Die Textgröße von Nachrichten ist jetzt ein Schieberegler (11-20px), und Benachrichtigungsdauer (2-10 Sekunden) ist neu.",
							es = "El tamaño del texto de los mensajes ahora es un control deslizante (11-20px), y la duración de las notificaciones (2-10 segundos) es nueva.",
							fr = "La taille du texte des messages est maintenant un curseur (11-20px), et la durée des notifications (2-10 secondes) est nouvelle.",
							pt = "O tamanho do texto das mensagens agora é um controle deslizante (11-20px), e a duração das notificações (2-10 segundos) é nova.",
						},
					},
					{
						type = "changed",
						text = {
							en = "Tooltips show after hovering briefly (0.3 seconds) instead of right away.",
							nl = "Tooltips verschijnen na kort zweven (0,3 seconden) in plaats van meteen.",
							de = "Tooltips erscheinen nach kurzem Darüberfahren (0,3 Sekunden) statt sofort.",
							es = "Las descripciones emergentes aparecen tras pasar el ratón un momento (0,3 segundos) en lugar de al instante.",
							fr = "Les infobulles s'affichent après un bref survol (0,3 seconde) au lieu de tout de suite.",
							pt = "As dicas aparecem depois de passar o mouse por um instante (0,3 segundo) em vez de na hora.",
						},
					},
					{
						type = "changed",
						text = {
							en = "A fresh Roblox look: Roblox's own dark and light colors and Roblox blue throughout.",
							nl = "Een frisse Roblox-look: de eigen donkere en lichte kleuren van Roblox en overal Roblox-blauw.",
							de = "Ein frischer Roblox-Look: die dunklen und hellen Farben von Roblox und überall Roblox-Blau.",
							es = "Un aspecto Roblox renovado: los colores oscuros y claros de Roblox y el azul de Roblox en todas partes.",
							fr = "Un nouveau look Roblox : les couleurs sombres et claires de Roblox et le bleu Roblox partout.",
							pt = "Um visual Roblox renovado: as cores escuras e claras do próprio Roblox e o azul do Roblox em tudo.",
						},
					},
					{
						type = "changed",
						text = {
							en = "Switches in Settings spring across, squish while pressed and light up on hover.",
							nl = "Schakelaars in Instellingen veren heen en weer, worden ingedrukt platter en lichten op als je erover zweeft.",
							de = "Schalter in den Einstellungen federn hinüber, werden beim Drücken gestaucht und leuchten beim Darüberfahren auf.",
							es = "Los interruptores de Configuración saltan con un rebote, se aplastan al pulsarlos y se iluminan al pasar el ratón.",
							fr = "Les interrupteurs des paramètres basculent avec un rebond, s'écrasent quand on appuie et s'illuminent au survol.",
							pt = "Os botões das configurações deslizam com um salto, se achatam ao pressionar e acendem ao passar o mouse.",
						},
					},
					{
						type = "changed",
						text = {
							en = "Notifications always show at the bottom-centre of the plugin.",
							nl = "Meldingen verschijnen altijd onderaan in het midden van de plugin.",
							de = "Benachrichtigungen erscheinen immer unten in der Mitte des Plugins.",
							es = "Las notificaciones siempre aparecen abajo en el centro del plugin.",
							fr = "Les notifications s'affichent toujours en bas au centre du plugin.",
							pt = "As notificações sempre aparecem embaixo, no centro do plugin.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Windows like Settings now dim the whole plugin, sidebar included, and center in it; the sidebar no longer shows through on top.",
							nl = "Vensters zoals Instellingen dimmen nu de hele plugin, ook de zijbalk, en staan in het midden; de zijbalk komt er niet meer bovenop.",
							de = "Fenster wie die Einstellungen dunkeln jetzt das ganze Plugin samt Seitenleiste ab und sind darin zentriert; die Seitenleiste liegt nicht mehr darüber.",
							es = "Las ventanas como Configuración ahora oscurecen todo el plugin, barra lateral incluida, y se centran en él; la barra lateral ya no se ve por encima.",
							fr = "Les fenêtres comme les paramètres assombrissent maintenant tout le plugin, barre latérale comprise, et s'y centrent ; la barre latérale ne passe plus par-dessus.",
							pt = "Janelas como Configurações agora escurecem o plugin inteiro, barra lateral incluída, e ficam centralizadas; a barra lateral não aparece mais por cima.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Sliders: press, hold, drag and let go. They no longer need a second click to stop dragging.",
							nl = "Schuifregelaars: indrukken, vasthouden, slepen en loslaten. Je hoeft niet meer een tweede keer te klikken om te stoppen.",
							de = "Schieberegler: drücken, halten, ziehen und loslassen. Zum Beenden ist kein zweiter Klick mehr nötig.",
							es = "Controles deslizantes: pulsa, mantén, arrastra y suelta. Ya no hace falta un segundo clic para dejar de arrastrar.",
							fr = "Curseurs : appuie, maintiens, fais glisser et relâche. Plus besoin d'un second clic pour arrêter.",
							pt = "Controles deslizantes: pressione, segure, arraste e solte. Não é mais preciso um segundo clique para parar.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Each Settings tab shows its own title again (Badges, What's New, About).",
							nl = "Elk tabblad in Instellingen toont weer zijn eigen titel (Badges, Wat is er nieuw, Over).",
							de = "Jeder Tab in den Einstellungen zeigt wieder seinen eigenen Titel (Abzeichen, Neuigkeiten, Über).",
							es = "Cada pestaña de Configuración vuelve a mostrar su propio título (Insignias, Novedades, Acerca de).",
							fr = "Chaque onglet des paramètres affiche de nouveau son propre titre (Badges, Nouveautés, À propos).",
							pt = "Cada aba das configurações volta a mostrar o próprio título (Emblemas, Novidades, Sobre).",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Open windows stay open when you click outside Studio or switch apps, and clicking the tabs never closes the window.",
							nl = "Open vensters blijven open als je buiten Studio klikt of van app wisselt, en klikken op de tabbladen sluit het venster nooit.",
							de = "Offene Fenster bleiben offen, wenn du außerhalb von Studio klickst oder die App wechselst, und ein Klick auf die Tabs schließt das Fenster nie.",
							es = "Las ventanas abiertas siguen abiertas al hacer clic fuera de Studio o cambiar de app, y hacer clic en las pestañas nunca cierra la ventana.",
							fr = "Les fenêtres ouvertes restent ouvertes quand tu cliques hors de Studio ou changes d'application, et cliquer sur les onglets ne ferme jamais la fenêtre.",
							pt = "Janelas abertas continuam abertas quando você clica fora do Studio ou troca de app, e clicar nas abas nunca fecha a janela.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "With Animations off, switch and slider knobs no longer change shape when pressed.",
							nl = "Met Animaties uit veranderen de knoppen van schakelaars en schuifregelaars niet meer van vorm als je erop drukt.",
							de = "Bei ausgeschalteten Animationen ändern Schalter- und Reglerknöpfe beim Drücken nicht mehr ihre Form.",
							es = "Con las animaciones desactivadas, los botones de interruptores y controles deslizantes ya no cambian de forma al pulsarlos.",
							fr = "Avec les animations désactivées, les boutons des interrupteurs et des curseurs ne changent plus de forme quand on appuie.",
							pt = "Com as animações desligadas, os botões dos interruptores e controles deslizantes não mudam mais de forma ao pressionar.",
						},
					},
					{
						type = "fixed",
						text = {
							en = "Images in messages line up on the left with the text.",
							nl = "Afbeeldingen in berichten staan links uitgelijnd met de tekst.",
							de = "Bilder in Nachrichten sind links am Text ausgerichtet.",
							es = "Las imágenes de los mensajes se alinean a la izquierda con el texto.",
							fr = "Les images des messages s'alignent à gauche avec le texte.",
							pt = "As imagens nas mensagens ficam alinhadas à esquerda com o texto.",
						},
					},
					{
						type = "changed",
						text = {
							en = "Windows keep a sensible size: never too narrow, too wide or too short. The Settings window stays the same height on every tab.",
							nl = "Vensters houden een goede grootte: nooit te smal, te breed of te kort. Het venster Instellingen blijft op elk tabblad even hoog.",
							de = "Fenster behalten eine sinnvolle Größe: nie zu schmal, zu breit oder zu kurz. Das Einstellungsfenster bleibt auf jedem Tab gleich hoch.",
							es = "Las ventanas mantienen un tamaño razonable: nunca demasiado estrechas, anchas o bajas. La ventana de Configuración tiene la misma altura en cada pestaña.",
							fr = "Les fenêtres gardent une taille raisonnable : jamais trop étroites, trop larges ou trop basses. La fenêtre des paramètres garde la même hauteur sur chaque onglet.",
							pt = "As janelas mantêm um tamanho sensato: nunca estreitas, largas ou baixas demais. A janela de Configurações tem a mesma altura em todas as abas.",
						},
					},
				},
			},
			{
				version = "1.11.0",
				date = "01/11/2026",
				title = "Notifications & animations",
				changes = {
					{
						type = "added",
						text = "Notifications: new messages you're not looking at pop up at the bottom-centre of the chat, or of Studio's 3D view while the chat is closed. Click one to open that conversation.",
					},
					{
						type = "added",
						text = "Smooth animations: windows pop in and fade out, the sidebar slides open, menus, new messages and notifications fade in, and hovers ease in and out.",
					},
					{
						type = "added",
						text = "Settings > Notifications (All, DMs only or Off) and Settings > Animations (On or Off).",
					},
					{
						type = "changed",
						text = "The Settings tabs are on the left, like Discord; in a narrow panel they show icons only.",
					},
					{ type = "added", text = "A notification when a badge you bought arrives." },
				},
			},
			{
				version = "1.10.2",
				date = "01/11/2026",
				title = "Display names, Premium & more",
				changes = {
					{
						type = "added",
						text = "Display names: DMs, the sidebar, message headers and replies show people's display names (Settings > Names to switch back to usernames). DM headers also show the @username.",
					},
					{
						type = "added",
						text = "The verified badge now shows everywhere a verified person's name does: messages, replies, the DM header, the sidebar and New message.",
					},
					{
						type = "added",
						text = "Premium badge, plus a checkout: Buy opens the badge on Roblox.com, and the badge shows up by itself once you've bought it.",
					},
					{
						type = "added",
						text = "New settings: Names, Badges, Badge Tooltips, Link Previews and Typing Indicator.",
					},
					{
						type = "added",
						text = "New commands: /say, /me, /shrug, /roll, /coinflip, /whois, /select, /stats, /about and /badges.",
					},
					{ type = "added", text = "About opens by itself the first time you install the plugin." },
					{
						type = "changed",
						text = "Expanding the sidebar in a narrow panel slides it over the chat instead of cutting the chat off. Click the chat (or pick a conversation) to close it.",
					},
					{
						type = "changed",
						text = "One Settings button in the sidebar: General, Badges, What's New and About are now tabs in the Settings window.",
					},
					{ type = "changed", text = "The version moved from the chat header to the panel's title." },
					{
						type = "changed",
						text = "Badge tooltips just show the badge's name, and the verified badge is smaller and looks like Roblox's.",
					},
					{ type = "changed", text = "System messages are from System again." },
					{ type = "fixed", text = "Badge tooltips sometimes showed in the wrong place." },
				},
			},
			{
				version = "1.9.1",
				date = "01/11/2026",
				title = "Badges & command help",
				changes = {
					{
						type = "added",
						text = "Badges next to names, with a tooltip when you hover over one. Verified Roblox accounts get a blue verified badge automatically.",
					},
					{ type = "added", text = "Custom badges for specific people, like the Plugin Developer badge." },
					{
						type = "added",
						text = "Badges you can buy (Diamond, Star, Supporter) in the new Badges window in the sidebar. They're Roblox game passes, bought on Roblox.com; press Refresh after buying.",
					},
					{
						type = "added",
						text = "Typing a command now shows its options above the message box, with what each one is for, which ones are optional, and the one you're typing highlighted.",
					},
					{
						type = "added",
						text = "An About button in the sidebar: plugin info, terms of use, what data is stored, and a note that the plugin isn't affiliated with Roblox.",
					},
					{
						type = "changed",
						text = 'System messages are now from "Roblox", with the Roblox logo and the verified badge.',
					},
					{ type = "changed", text = "/help shows clearer usage, like /ban <user> [reason]." },
				},
			},
			{
				version = "1.8.0",
				date = "01/11/2026",
				title = "Edit your messages",
				changes = {
					{
						type = "added",
						text = "Right-click one of your own messages and choose Edit Message: it goes into the message box, and Send (or Enter) saves it. The × on the Editing bar cancels.",
					},
					{
						type = "added",
						text = "Edited messages show a small (edited) for everyone, and edits appear live, in the team chat and in DMs.",
					},
					{
						type = "changed",
						text = "Reply lines look like Discord: a curved line from the avatar and a mini avatar of the person you're replying to.",
					},
				},
			},
			{
				version = "1.7.0",
				date = "01/11/2026",
				title = "Messages with avatars",
				changes = {
					{
						type = "changed",
						text = "Messages look like Discord: the sender's Roblox avatar on the left, their name and the time on top, the message below.",
					},
					{
						type = "changed",
						text = "System messages get a small badge; images without text no longer leave an empty line.",
					},
				},
			},
			{
				version = "1.6.0",
				date = "01/11/2026",
				title = "Rebuilt under the hood",
				changes = {
					{
						type = "fixed",
						text = "/goto works: your camera position is shared with collaborators (once a second, only when it moves).",
					},
					{
						type = "fixed",
						text = "Clicking a link inside a message opens it (before, only link previews could be clicked).",
					},
					{
						type = "fixed",
						text = "Ranks, mutes and bans you give other people are remembered after reloading the plugin.",
					},
					{ type = "fixed", text = "Users listed in Config.AllowedUsers get their rank." },
					{ type = "fixed", text = "Messages containing & show exactly what was typed." },
					{
						type = "changed",
						text = "/timer reminders and the typing animation stop when the plugin is reloaded or closed.",
					},
					{
						type = "changed",
						text = "The plugin's code was reorganized into small modules with a shared foundation; it now builds with Rojo.",
					},
				},
			},
			{
				version = "1.5.0",
				date = "01/11/2026",
				title = "Direct messages & friends",
				changes = {
					{
						type = "added",
						text = "Direct messages! A Discord-style sidebar with this game's team chat pinned at the top and a DM for every collaborator.",
					},
					{
						type = "added",
						text = "The sidebar shows avatars, a green dot for who's online, and red badges for unread messages in DMs and the team chat.",
					},
					{
						type = "added",
						text = "When the panel is wide, the sidebar shows names and each conversation's latest message; the toggle at its bottom expands or collapses it.",
					},
					{ type = "added", text = "Everything works in DMs: replies, images, files, polls and deleting." },
					{
						type = "added",
						text = "New message: the + in the sidebar lets you DM any of your Roblox friends (with search) or anyone by username. They see it when they open this place with Team Chat.",
					},
					{ type = "added", text = "Friends are marked in your DMs." },
					{
						type = "added",
						text = "Close a DM with the × that shows when you hover it. It comes back when they message you again or you start it again; no messages are deleted.",
					},
					{
						type = "added",
						text = "Games without their own icon get a tile with their initials; your game's icon shows as soon as you set one.",
					},
					{
						type = "changed",
						text = "/whisper sends a real direct message instead of a message everyone could see.",
					},
				},
			},
			{
				version = "1.2.5",
				date = "01/11/2026",
				title = "Audio, GIFs and new file cards",
				changes = {
					{
						type = "added",
						text = "Audio files play right in the chat: play/pause, a waveform that fills as it plays, the playback time, and click the waveform to skip.",
					},
					{ type = "added", text = "Only you hear the audio you play; nothing is sent to anyone else." },
					{ type = "added", text = "Only one audio clip plays at a time: starting one pauses the other." },
					{ type = "added", text = "Animated GIFs: attach a .gif and everyone in the chat sees it move." },
					{
						type = "added",
						text = "Long GIFs are trimmed to 48 frames but keep their total length; if a GIF can't be uploaded, only you can see it.",
					},
					{
						type = "changed",
						text = 'Redesigned file cards: a colored icon per file type, the file extension and a "local only" tag under the name, and a compact download button.',
					},
					{
						type = "changed",
						text = "File and audio cards have properly rounded borders and follow the light and dark themes.",
					},
					{
						type = "changed",
						text = "File and audio cards stay between 100 and 250 pixels wide instead of stretching across the chat.",
					},
					{
						type = "changed",
						text = "Videos get a file card. For videos uploaded to Roblox, its button opens the video's page in your browser.",
					},
					{
						type = "changed",
						text = "What's New is shorter: one entry per day instead of one per small update.",
					},
					{
						type = "changed",
						text = "Small updates are now collected here and only published with the next big update.",
					},
					{
						type = "removed",
						text = "The in-chat video player: Studio can't show video inside plugins, so it only showed a black screen.",
					},
					{ type = "removed", text = "The Output warning when a version has no changelog entry." },
					{ type = "fixed", text = "The version number in the header and the What's New popup work again." },
				},
			},
			{
				version = "1.0.10",
				date = "31/10/2026",
				title = "Official release!",
				changes = {
					{
						type = "added",
						text = "Roblox's Builder icons throughout the chat: the empty chat, the send button, menus, modals and file cards.",
					},
					{
						type = "added",
						text = "Roblox's Builder fonts, with Builder Extended for titles and Builder Mono for times, numbers and commands.",
					},
					{
						type = "added",
						text = "A header with the plugin name, the version number, a What's New button and a Settings button.",
					},
					{
						type = "added",
						text = "What's New: this changelog pops up once after each update and can be opened any time from the header.",
					},
					{ type = "added", text = "Icons next to the titles of the Settings, Poll and What's New windows." },
					{
						type = "added",
						text = "Chat history is saved in each place and shared with Team Create collaborators, with a local backup of each place's chat.",
					},
					{ type = "added", text = "Polls can have up to 10 answers." },
					{
						type = "added",
						text = "Click a reply to jump to the original message, which flashes so you can spot it.",
					},
					{ type = "added", text = "Commands can be turned off with Enabled = false." },
					{
						type = "added",
						text = "If a link can't be opened, it's copied to your clipboard so you can paste it.",
					},
					{ type = "changed", text = "New reply design: a reply icon with the username at half opacity." },
					{
						type = "changed",
						text = "The right-click menu opens next to your cursor and has icons and a red Delete option.",
					},
					{ type = "changed", text = "The plus menu looks like the right-click menu." },
					{
						type = "changed",
						text = "Menus and windows close when you click outside them, even elsewhere in Studio.",
					},
					{
						type = "changed",
						text = "Windows scroll when they're taller than the panel, and Settings dims the chat behind it like the other windows.",
					},
					{ type = "changed", text = "The two required poll answers no longer have a remove button." },
					{
						type = "changed",
						text = "Link previews are a compact card with the site's name, a short address and an open arrow; they highlight softly on hover.",
					},
					{
						type = "changed",
						text = "Redesigned command and emoji suggestions: a title, icons, names with descriptions, rank badges and a hint.",
					},
					{
						type = "changed",
						text = "Hover over a suggestion to highlight it, then press Tab or click to pick it; suggestions close when you click outside the chat.",
					},
					{
						type = "changed",
						text = "Long messages wrap while you type and the message box grows to show every line.",
					},
					{
						type = "changed",
						text = 'For multi-line messages, set Settings > Send Messages to "Button Only": Enter adds a new line and the Send button sends.',
					},
					{
						type = "removed",
						text = "Shift+Enter: Studio doesn't tell plugins which keys are held, so it can't be told apart from Enter.",
					},
					{ type = "removed", text = "The highlight when hovering over a message." },
					{
						type = "fixed",
						text = "Theme, clock format, timestamps, send mode and text size can be changed again, and are remembered.",
					},
					{
						type = "fixed",
						text = "Links open in your web browser instead of the Roblox Creator Hub, and no longer click on the wrong text after changing how times are shown.",
					},
					{
						type = "fixed",
						text = "The Download button opens the file's Roblox page, or copies a local-only file's ID.",
					},
					{
						type = "fixed",
						text = "The plus button, polls, file attachments and drag and drop work again, and sending a file no longer crashes the chat.",
					},
					{ type = "fixed", text = "Hovering links and replies no longer spams errors in Output." },
					{ type = "fixed", text = "Old copies of the plugin no longer keep running after a reload." },
					{
						type = "fixed",
						text = "Clicking inside a window or menu (or its padding) no longer closes it, and the toolbar's Settings button no longer reopens Settings right after closing it.",
					},
					{ type = "fixed", text = "Long windows no longer hide the buttons at the bottom." },
					{ type = "fixed", text = "An error that stopped messages from showing up." },
				},
			},
		},
	},
}
