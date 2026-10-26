# Fält

Mobilanpassad, klickbar demo för Lindqvist El i Göteborg.

## Kör appen

Ladda ner `falt-demo.html` och öppna filen i din webbläsare. Den innehåller hela appen och kräver inga installationer.

Alternativt: kör `python3 -m http.server 3000` i repots katalog och öppna http://localhost:3000.

## Funktioner

- Två jobb idag, markera klara.
- Offerter från mall, prisbok och egna rader.
- ROT 30 % / RUT 50 % på arbete inklusive moms, förenklad demokalkyl för 2026.
- Kundvy med godkännande, namnteckning och avböjande.
- Omvandla skickad eller signerad offert till faktura och markera betald.
- Veckoschema med Erik och Nora, inklusive kontroll av dubbelbokningar.
- Redigerbara kunder, prisbok och företagsuppgifter.
- Lokal lagring, JSON-export och återställning.
- Utskrift / PDF via webbläsarens utskriftsdialog.

Börja med Spotlights kök på startsidan.

## Publicera med GitHub Pages

Öppna Settings → Pages i repot. Under Build and deployment väljer du Deploy from a branch, main och / (root), sedan Save. GitHub visar den färdiga webbadressen när publiceringen är klar.

## Begränsningar och verifiering

Detta är en frontenddemo. Inga verkliga mejl, betalningar, Skatteverket-kontroller eller juridiska e-signeringar görs. Uppgifter sparas i samma webbläsare och delas inte mellan enheter. Använd exempeldata.

JavaScript har syntaxkontrollerats med `node --check app.js`. Webbläsartest och visuell verifiering kunde inte slutföras eftersom körmiljön blockerade webbläsarstart och lokal server. Ingen hosted preview har verifierats.
