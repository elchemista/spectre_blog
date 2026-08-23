---
title: "In Europa un Agent deve fare più che funzionare: Spectre 0.3.3, GDPR, AI Act e ISO"
slug: "spectre-0-3-3-gdpr-ai-act-iso-europa"
lang: "it"
status: published
date: 2026-08-23
updated: 2026-08-23
category: "AI Governance"
tags: ["Spectre","GDPR","AI Act","ISO 42001","ISO 27701","AI governance","privacy","EU market"]
seo_title: "Spectre 0.3.3 per GDPR, AI Act e ISO"
seo_description: "Spectre 0.3.3 porta cancellazione governata, prove, policy e osservabilità in un runtime pensato per GDPR, AI Act e percorsi ISO."
cover_alt: "Un Agent Spectre controllato attraverso policy, prove verificabili e cancellazione governata per il mercato europeo"
---

Immagina di essere un'agenzia europea e di presentare a un cliente il nuovo
Agent che hai appena costruito.

La demo funziona bene. Il cliente scrive una richiesta, l'Agent consulta alcuni
documenti, chiama un servizio esterno e prepara una risposta. Tutto sembra
veloce, intelligente e pronto per essere messo in produzione.

Poi nella riunione entra il responsabile della sicurezza, oppure il DPO, e
cominciano le domande che non comparivano nella demo.

Dove rimangono i dati della conversazione? Quale modello li ha ricevuti? Come
possiamo eliminare davvero lo stato di un cliente? Cosa succede se un vecchio
backup lo fa ricomparire? Possiamo dimostrare quale versione dell'Agent ha preso
una decisione? Una persona può fermare un'azione prima che raggiunga il mondo
esterno? Se cambiamo provider, perdiamo anche la nostra capacità di spiegare il
sistema?

In quel momento non importa più quanto fosse bella la risposta del modello.
Importa se l'architettura possiede risposte credibili.

È qui che molti progetti AI europei rallentano. Non perché il modello non sia
abbastanza intelligente, ma perché il sistema intorno al modello è nato come
una demo e ora deve essere trasformato in qualcosa che un'azienda possa
governare.

Con [Spectre 0.3.3](https://github.com/elchemista/spectre/tree/0.3.3) ho cercato
di spostare quel momento molto più vicino all'inizio. Spectre non promette che
installare una libreria renda automaticamente conforme al GDPR o all'AI Act.
Nessun runtime può conoscere la base giuridica di un trattamento, firmare un
accordo con un fornitore o ottenere una certificazione ISO al posto
dell'azienda.

Può però cambiare il punto da cui l'azienda parte. Invece di aggiungere
controllo, cancellazione e prove dopo che l'Agent è già cresciuto, può costruire
l'Agent sopra confini che esistono fin dal primo giorno.

## Il GDPR entra nel runtime prima della richiesta di cancellazione

Quando si parla di GDPR nei progetti AI, la conversazione finisce spesso su una
privacy policy e su una casella da selezionare. Il regolamento chiede molto di
più.

I suoi [principi sul trattamento dei dati](https://data.europa.eu/eli/reg/2016/679/oj)
parlano di finalità definite, minimizzazione, conservazione limitata, integrità
e riservatezza. La protezione dei dati fin dalla progettazione chiede che questi
principi entrino nelle misure tecniche e organizzative, non che vengano
ricordati soltanto alla fine del progetto.

Per un Agent questo significa fare una scelta importante: osservare il sistema
senza copiare ovunque la conversazione.

Il Journal di Spectre è nato proprio con questa separazione. Non è la cronologia
della chat e non è un contenitore generico di log. Registra decisioni
strutturate del runtime, come routing, policy, lifecycle, esecuzione e
persistenza, ma esclude per impostazione iniziale il testo della conversazione,
gli argomenti degli Effect, i risultati delle Action e gli errori grezzi dei
provider. Se un'applicazione decide di includere contenuto, deve farlo in modo
esplicito e può applicare redazione e conservazione nel proprio Store.

Questa differenza sembra piccola finché non bisogna spiegare perché una frase
scritta da un cliente è stata copiata in cinque sistemi di osservabilità.
Spectre parte dall'idea opposta. Per capire una decisione, prima prova a
conservare la forma della decisione, non tutto il contenuto che le passava
intorno.

Anche le boundary receipt seguono lo stesso principio. Possono collegare un
confine non deterministico o una decisione di autorità allo stato canonico e
alla Definition attiva, senza trasformare ogni dettaglio privato in un log
pubblico. Il sink rimane responsabilità dell'host, che deve applicare
cifratura, isolamento tra clienti, controllo degli accessi e conservazione.
Spectre non finge che il posto in cui salviamo una prova sia automaticamente
sicuro. Rende esplicito il contratto che quel posto deve rispettare.

## Cancellare un Agent senza lasciarlo tornare

La novità più concreta della versione 0.3.3 è la
[cancellazione governata di una Instance](https://github.com/elchemista/spectre/blob/0.3.3/docs/ERASURE.md).

Supponiamo che un cliente chieda di eliminare i propri dati e che
l'organizzazione abbia stabilito che la richiesta rientra nel
[diritto alla cancellazione](https://data.europa.eu/eli/reg/2016/679/oj).
Eliminare una riga dal database non basta se l'Agent è ancora vivo in memoria,
se un worker può scrivere un nuovo checkpoint o se un backup vecchio può
riportare in vita lo stato appena rimosso.

Spectre affronta questa operazione come un passaggio di manutenzione, non come
una normale azione dell'Agent. Prima permette di costruire un piano che non
tocca i dati e verifica se gli adapter configurati espongono le capacità
necessarie. Al momento dell'esecuzione richiede la chiave stabile esatta come
conferma, rifiuta una Instance ancora attiva sul nodo locale e acquisisce un
controllo di manutenzione che non può scavalcare un proprietario vivo.

Solo allora coordina ciò che il core conosce. Rimuove i record del Journal
legati a quella precisa Instance, elimina i payload ancora pendenti nelle
receipt e cancella il checkpoint canonico. Il Checkpoint Store deve poi
installare un marcatore durevole e leggerlo nuovamente. Quel marcatore impedisce
a una scrittura tardiva di ricreare la stessa identità dopo la cancellazione.

Il risultato non è soltanto un messaggio che dice operazione completata.
Spectre restituisce una prova limitata ai componenti che ha realmente
coordinato. I test di conformità verificano anche che la cancellazione sia
ripetibile, che non tocchi una Instance vicina e che una gara tra cancellazione
e scrittura produca un solo risultato autorevole.

La parte più seria di questo disegno è ciò che Spectre non dichiara di aver
cancellato.

Lo stato applicativo può vivere in un altro database. La memoria può essere
gestita da un adapter esterno. Un provider può conservare richieste secondo il
contratto scelto dall'azienda. Anche telemetria, esportazioni, repliche e backup
hanno un proprio ciclo di vita. La
[mappa dei dati di Spectre](https://github.com/elchemista/spectre/blob/0.3.3/docs/DATA_LIFECYCLE.md)
mostra questi confini invece di nasconderli dietro una risposta troppo
ottimista.

Questa onestà è una caratteristica di conformità. Un DPO non ha bisogno di una
libreria che dica di aver cancellato tutto. Ha bisogno di sapere esattamente
cosa è stato cancellato, cosa rimane e chi ne è responsabile.

## L'AI Act guarda il sistema intorno al modello

Lo stesso ragionamento vale per l'AI Act.

Quando si legge il
[testo del regolamento europeo sull'intelligenza artificiale](https://data.europa.eu/eli/reg/2024/1689/oj),
si nota che, per i sistemi che rientrano nei casi ad alto rischio, i requisiti
più impegnativi non chiedono semplicemente un modello più accurato. Parlano di
gestione continua del rischio, documentazione,
registrazione degli eventi, supervisione umana, robustezza, sicurezza e
monitoraggio nel tempo.

Questo è un problema di sistema.

In Spectre il modello può classificare una richiesta o proporre un'azione, ma
non possiede l'autorità finale. Un Effect descrive qualcosa che potrebbe
accadere. La Policy e il lifecycle deterministico stabiliscono quali passaggi
sono necessari, mentre l'host conserva credenziali e potere di esecuzione.

La 0.3.3 rende ancora più chiara la supervisione umana con policy risolvibili
da una fonte esterna. Una richiesta protetta può rimanere in attesa mentre la
conversazione continua normalmente. L'approvazione deve arrivare dalla fonte
host dichiarata e non può essere inventata dal modello dentro una risposta.

È una differenza importante per un'agenzia che costruisce, per esempio, un
Agent capace di preparare un rimborso, cambiare un contratto o inviare una
comunicazione ufficiale. La persona non viene aggiunta come frase nel prompt.
Diventa un passaggio del runtime che il modello non può saltare.

Il Journal aiuta a spiegare quale route e quale policy sono state applicate.
Le receipt collegano i confini esterni ai digest dello stato e alla Definition
in uso. Le Definition e i Manifest sono immutabili e identificabili, quindi una
decisione può essere ricondotta alla configurazione che esisteva in quel
momento, non a quella che il repository contiene oggi.

Quando il comportamento cambia, la governance di Spectre separa proposta,
valutazione, approvazione e attivazione. Una modifica proposta dal modello
rimane inerte. I test protetti non possono essere sostituiti da esempi più
facili creati dal candidato stesso. Se la nuova versione peggiora, la
Definition precedente rimane disponibile per il rollback.

Questo non completa da solo un sistema di gestione del rischio richiesto
dall'AI Act. Offre però fatti tecnici su cui quel sistema può lavorare. Senza
versioni identificabili, prove delle decisioni e test ripetibili, anche la
migliore procedura aziendale rimane costretta a fidarsi di racconti scritti
dopo l'incidente.

## Quando un controllo diventa una prova

Per un cliente enterprise non basta che un adapter sembri corretto.

Un'agenzia può sostituire il Checkpoint Store, il Journal, il sink delle receipt
o il sistema che assegna il possesso distribuito. Appena questo succede, le
garanzie del core dipendono anche da codice scritto fuori dal core.

Spectre 0.3.3 rende questa frontiera verificabile attraverso
[contratti di conformità eseguibili](https://github.com/elchemista/spectre/blob/0.3.3/docs/FOUNDATION_CONFORMANCE.md).
Un adapter di cancellazione non viene considerato valido perché espone una
funzione con il nome giusto. Deve dimostrare cancellazione precisa, isolamento
delle identità vicine, ripetibilità e rifiuto delle scritture ormai superate.
Il profilo distribuito del proprietario verifica gare concorrenti, passaggio di
autorità e fencing.

Anche qui Spectre evita una promessa impossibile. Questi test non certificano
la replica del database, la politica dei backup o la topologia del deployment.
Provano soltanto la semantica che possono osservare. Ma trasformano una parte
importante dell'integrazione da fiducia informale a contratto eseguibile.

Per un audit questa distinzione conta. Dire che un componente dovrebbe
comportarsi in un certo modo è documentazione. Mostrare un report prodotto
dallo stesso contratto pubblico usato in sviluppo è evidenza.

## Un ponte verso ISO, non una certificazione automatica

Le norme ISO rilevanti per l'AI non certificano una libreria isolata. Guardano
come un'organizzazione assegna responsabilità, gestisce rischi, mantiene
processi, verifica risultati e migliora nel tempo.

[ISO/IEC 42001](https://www.iso.org/standard/42001) definisce un sistema di
gestione dell'intelligenza artificiale. Spectre non crea quel sistema al posto
dell'azienda, ma può alimentarlo con Definition identificabili, policy,
valutazioni, receipt, Journal e prove di attivazione. Sono artefatti che aiutano
a collegare ciò che l'organizzazione dichiara a ciò che il runtime ha
effettivamente fatto.

[ISO/IEC 42005](https://www.iso.org/standard/42005) porta l'attenzione sulle
valutazioni di impatto lungo il ciclo di vita. Qui diventano utili la
separazione tra comportamento dichiarato e osservato, i report di valutazione
e la storia delle modifiche approvate. [ISO/IEC 23894](https://www.iso.org/standard/77304.html)
tratta la gestione del rischio AI, un processo che può usare gli stessi test e
le stesse prove per verificare se una misura tecnica continua a funzionare.

Sul lato della sicurezza,
[ISO/IEC 27001](https://www.iso.org/standard/27001) richiede un sistema di
gestione che coinvolge persone, processi e tecnologia. Sul lato della privacy,
[ISO/IEC 27701](https://www.iso.org/standard/27701) offre un sistema dedicato
alla gestione delle informazioni personali e alla capacità di dimostrare
responsabilità.

Spectre non consegna nessuno di questi certificati. Rende però più facile
riutilizzare la stessa struttura tecnica quando l'azienda mappa i propri
controlli verso standard differenti. La cancellazione governata può sostenere
un controllo privacy. Il Journal può sostenere tracciabilità e indagine. Le
policy esterne possono sostenere la supervisione. Le valutazioni e le
Definition immutabili possono sostenere gestione delle modifiche e rischio AI.

La parola importante è sostenere. L'auditor deve ancora verificare contesto,
processi e prove. Spectre rende quelle prove più vicine al comportamento reale
del sistema.

## Perché questo conta per le agenzie europee

Un'agenzia non vende soltanto codice. Vende al cliente la possibilità di
fidarsi di quel codice anche dopo che il team originale ha terminato il
progetto.

Con un framework centrato soprattutto sul ciclo tra prompt, modello e tool,
ogni nuovo requisito enterprise tende a diventare un'integrazione separata. Il
log viene aggiunto da una parte, l'approvazione da un'altra, la cancellazione
in uno script amministrativo e la versione del comportamento in una tabella
creata più tardi. Alla fine il sistema può anche funzionare, ma nessun
componente possiede l'intera storia.

Spectre è più adatto a questo lato del mercato perché parte da una domanda
diversa. Non chiede soltanto come far eseguire un tool al modello. Chiede chi
possiede lo stato, quale Definition è attiva, chi può attraversare un confine,
quale prova rimane e come quella identità viene cancellata senza tornare.

Per un'agenzia europea significa poter arrivare dal cliente con qualcosa di
più serio di una demo. Può mostrare un piano dei dati, una policy di
approvazione, un report di valutazione, un report di conformità del proprio
adapter di storage e una procedura di cancellazione. Può cambiare provider o
infrastruttura senza
spostare nel modello l'autorità dell'Agent. Può adattare il deployment alle
esigenze del cliente mantenendo la stessa architettura di controllo.

Questo non rende Spectre migliore in ogni possibile progetto AI. Se serve uno
script che riassume dieci file e poi scompare, un runtime governato può essere
più di quanto occorre. Ma quando un Agent entra nei processi di un'azienda,
tocca dati personali, rimane attivo nel tempo e può produrre effetti, i
problemi che Spectre tratta come fondamentali diventano esattamente quelli che
il cliente comincerà a chiedere.

## La responsabilità rimane umana

Resta una linea che non voglio nascondere.

Spectre non decide se un trattamento possiede una base giuridica. Non scrive
l'informativa, non classifica da solo il rischio previsto dall'AI Act, non
completa una valutazione di impatto e non stabilisce se un trasferimento fuori
dall'Europa sia lecito. Non configura la conservazione del provider, non cifra
il database dell'host e non forma le persone incaricate della supervisione.

Anche l'obbligo di informare un utente che sta interagendo con un sistema AI
deve essere realizzato nell'esperienza del prodotto. Il runtime può conservare
la verità tecnica del comportamento, ma l'azienda deve trasformarla in
trasparenza comprensibile.

Questa non è una debolezza. È la separazione corretta delle responsabilità.

La conformità non nasce da una dipendenza aggiunta al progetto. Nasce
dall'incontro tra scelte legali, processi organizzativi e controlli tecnici.
Spectre 0.3.3 lavora sulla terza parte e cerca di renderla abbastanza esplicita
da poter sostenere le altre due.

Per molto tempo il mercato AI ha premiato soprattutto chi riusciva a mostrare
la demo più sorprendente. In Europa sta diventando altrettanto importante
mostrare che quella demo può essere limitata, osservata, testata, fermata e,
quando necessario, cancellata davvero.

È su questo terreno che Spectre può diventare una scelta particolarmente forte
per agenzie e aziende europee. Non perché promette una scorciatoia verso la
conformità, ma perché evita di costruire l'Agent in una forma che rende la
conformità quasi impossibile da dimostrare dopo.
