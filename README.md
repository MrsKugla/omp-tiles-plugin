# omp Tiles

Plugin per [Tern](https://stencil.so/tern) che mostra in un blocco un tile colorato per ogni sessione
[omp](https://github.com/can1357/oh-my-pi) aperta, in tutte le sessioni di Tern.

Ogni tile mostra:

- il **titolo della sessione omp** (quello che omp mostra tra virgolette nel campo di input) e lo stato: *lavora*,
  *attende te*, *inattivo*;
- gli **ultimi 4 livelli della directory** della sessione omp (il percorso intero passando sopra il tile) e, sotto
  lo stato, il **nome della sessione Tern**, nel colore del tile;
- il **modello** e il livello di thinking;
- la **percentuale di contesto**, con una barra che diventa gialla dal 50% e rossa dall'85%;
- una piccola **scena di [Flow](https://github.com/robdmac/flow)** che segue il lavoro dell'agente: cresce con il
  thinking, le chiamate ai tool e la durata del turno; fa fumo dopo un errore o una compattazione; diventa blu con il
  contesto quasi pieno; si calma e respira quando omp aspetta una tua risposta. Da inattivo resta al minimo (nel
  fuoco, il lumino blu).

Ogni tile ha la sua scena: `fire` (predefinita), `warp`, `avalon`, `engine`, `bubbles`.

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
| Bottoni *compact* / *snapcompact* | Mandano `/compact` o `/compact snapcompact` a quella sessione omp senza spostarti. Attivi solo con omp *inattivo*; altrimenti sono grigi e un clic avvisa che omp sta lavorando |
| Icona *sliders* in alto a destra, oppure tasto destro › *Personalizza* | Apre il pannello del tile; *Fatto* lo chiude |
| Pannello › *Scena* | Sceglie la scena: fire, warp, avalon, engine, bubbles, ognuna con la sua icona |
| Pannello › *Colore* | Sceglie il colore del tile tra i pallini, o nessun colore (cerchio barrato) |
| Pannello › *Dimensione* | Una griglia piccola, larga quanto le colonne del blocco e alta due righe: il quadratino cliccato diventa l'angolo in basso a destra del tile |
| Pannello › *Posizione* | Le frecce scambiano il tile con quello prima o dopo |
| Tasto destro › *Copia stile* | Ricorda scena e colore del tile |
| Tasto destro › *Incolla stile* | Dà al tile la scena e il colore copiati. Compare solo dopo un *Copia stile* e vale una volta: per incollare di nuovo, copia di nuovo |

Ogni sessione di Tern ha la sua copia del blocco: aprilo con Ctrl+Alt+R nelle sessioni in cui lo vuoi. Tutte le
copie mostrano gli stessi tile, con gli stessi colori, scene, ordine e dimensioni.

I tile stanno in una griglia invisibile: almeno 2 colonne, una in più ogni 44 caratteri di larghezza del blocco
(fino a 8). Allargando o restringendo il blocco, le colonne cambiano entro un paio di secondi. Un tile più largo
delle colonne disponibili occupa tutta la riga.

Se non scegli un colore, il tile prende quello della sua tab.

La scorciatoia non è Ctrl+Shift+R perché Tern la usa già per lo zoom del pannello. Per cambiarla, aggiungi in
`settings.json` di Tern una voce `keybinds` per l'azione `plugin.omp-tiles.open`.

## Limiti

- Lo stato del lavoro è ricostruito da quello che Tern mostra di omp (stato dell'agente, ultime chiamate ai
  tool, testo generato), letto una volta al secondo: un'attività molto breve tra due letture può non comparire
  nella scena.
- Contesto e livello di thinking sono letti dalla barra in basso di omp. Se una versione futura di omp la
  cambia, quei due valori mostrano "—".
- Il titolo della sessione omp è letto dal campo di input di omp, perché il titolo che Tern dà all'agente è
  quello della shell (es. "Windows PowerShell"). Se omp non mostra un titolo, o una sua versione futura cambia
  quel campo, il tile torna al titolo di Tern.
- Le scene si animano solo nella copia che hai davanti, al ritmo di Flow (un fotogramma ogni 70 ms, 125 da
  calme). Tern dà a un plugin 50 ms per volta: se molti tile non ci stanno insieme, ognuno rallenta un po'
  invece di bloccare la finestra. Quando nessuna copia è visibile i dati si aggiornano ogni 1,5 secondi.
- Le scene `balloon`, `falcon`, `starship`, `surf`, `ski` e `train` di Flow non ci sono: dentro Tern sono troppo
  pesanti per il ritmo di Flow.
- I tile non si trascinano col mouse e non si ridimensionano tirando un bordo: Tern dà ai plugin solo clic,
  doppio clic e menu del tasto destro. Per questo spostamento e dimensioni sono nel pannello del tile.
- La larghezza del blocco è letta con `tern ls --json` ogni 2 secondi, perché l'API dei plugin non la fornisce.

## Crediti

Le scene sono una conversione in Luau di quelle di [Flow](https://github.com/robdmac/flow) di Rob Macrae, riga
per riga: per lo stesso seme e gli stessi comandi danno gli stessi fotogrammi dell'originale. La cartella `flow/`
deriva da `hooks/` di Flow (`cells.ts`, `pixels.ts`, `waiting.ts`, `sound.ts`, `fire.ts`, `fire-palette.ts`,
`styles.ts`, `starfield.ts`, `colony.ts`, `engine.ts`, `bubbles.ts`); il modello di attività in `window.luau`
deriva da `hooks/activity.ts`. Flow è
distribuito con la seguente licenza:

```text
MIT License

Copyright (c) 2026 Rob Macrae

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Licenza

MIT, © 2026 Benedetta Scattolin. Vedi [LICENSE](LICENSE).
