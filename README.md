# omp Tiles

Plugin per [Tern](https://stencil.so/tern) che mostra in un blocco un tile colorato per ogni sessione
[omp](https://github.com/can1357/oh-my-pi) aperta, in tutte le sessioni di Tern.

Ogni tile mostra:

- il **titolo della sessione omp** (quello che omp mostra tra virgolette nel campo di input) e lo stato: *lavora*,
  *attende te*, *inattivo*; mentre omp lavora, la card pulsa lentamente nel colore della sessione;
- gli **ultimi 4 livelli della directory** della sessione omp (il percorso intero passando sopra il tile) e, sotto
  lo stato, il **nome della sessione Tern**, nel colore della sessione;
- il **modello** e il livello di thinking;
- la **percentuale di contesto**, con una barra che diventa gialla dal 50% e rossa dall'85%;
- il bottone **compact**.

## Installazione

```sh
tern plugin install github.com/MrsKugla/omp-tiles-plugin
```

Oppure, da una copia della repo, lancia l'installer: `install.bat` su Windows (anche con doppio clic), `./install.sh`
su macOS e Linux. Copia la cartella nei plugin di Tern; rilancialo per aggiornare. Se il plugin è collegato con
`tern plugin link`, prima scollegalo con `tern plugin unlink omp-tiles`.

Per lavorarci sopra, clona la repo e collegala: Tern ricarica il plugin a ogni salvataggio.

```sh
tern plugin link percorso/della/repo
```

`tern plugin list` mostra se si è caricato.

## Uso

| Azione | Effetto |
| --- | --- |
| **Ctrl+Alt+R**, oppure *Apri omp Tiles* dalla palette | Apre il blocco della sessione di Tern in cui sei, accanto al pannello attivo, o lo mette a fuoco se c'è già |
| Clic su un tile | Va alla sessione omp di quel tile |
| Bottone *compact* | Manda `/compact` a quella sessione omp senza spostarti. Attivo solo con omp *inattivo*; altrimenti è grigio e un clic avvisa che omp sta lavorando |
| Icona tavolozza accanto al nome della sessione Tern (compare passando su quella riga) | Apre nella card i pallini: un clic prova il colore su tutte le card di quella sessione, *Conferma* lo tiene, *Annulla* torna a prima. Un altro clic sulla tavolozza chiude |
| Frecce ← → in basso a destra (compaiono passando sopra la card) | Scambiano la card con quella prima o dopo |

Ogni sessione di Tern ha la sua copia del blocco: aprilo con Ctrl+Alt+R nelle sessioni in cui lo vuoi. Tutte le
copie mostrano gli stessi tile, con gli stessi colori e lo stesso ordine.

I tile stanno in una griglia invisibile: almeno 2 colonne, una in più ogni 44 caratteri di larghezza del blocco
(fino a 8), tutti della stessa misura. Allargando o restringendo il blocco, le colonne cambiano entro un paio di
secondi.

Senza un colore scelto, le card della sessione restano neutre.

La scorciatoia non è Ctrl+Shift+R perché Tern la usa già per lo zoom del pannello. Per cambiarla, aggiungi in
`settings.json` di Tern una voce `keybinds` per l'azione `plugin.omp-tiles.open`.

## Limiti

- Stato, titolo, contesto e modello sono letti una volta al secondo, solo dalla copia del blocco che hai davanti.
- Contesto e livello di thinking sono letti dalla barra in basso di omp. Se una versione futura di omp la
  cambia, quei due valori mostrano "—".
- Il titolo della sessione omp è letto dal campo di input di omp, perché il titolo che Tern dà all'agente è
  quello della shell (es. "Windows PowerShell"). Se omp non mostra un titolo, o una sua versione futura cambia
  quel campo, il tile torna al titolo di Tern.
- Tern dà a un plugin 50 ms per chiamata. Per questo il plugin legge solo quello che il tile mostra, e niente
  animazioni.
- I tile non si trascinano col mouse: Tern dà ai plugin solo clic, doppio clic e menu del tasto destro. Per questo lo
  spostamento passa dalle frecce ← →.
- La larghezza del blocco è letta con `tern ls --json` ogni 2 secondi, perché l'API dei plugin non la fornisce.

## Licenza

MIT, © 2026 Benedetta Scattolin. Vedi [LICENSE](LICENSE).
