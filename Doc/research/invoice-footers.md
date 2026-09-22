# Rechnungsfußzeilen auf mehrseitigen PDFs

Recherche vom 18. September 2026. Anlass: Screenshot einer Classic-Rechnung, deren Firmen-/Bankdaten nur nach dem Gesamtbetrag auf der letzten Seite erscheinen. Recherche und Codeprüfung; keine Änderung am Renderer oder Template und keine Reproduktion mit dem konkreten laufenden Earnie-Build.

## Ergebnis

Für InvoiceKit ist eine auf jeder Seite unten wiederholte **Seitenfußzeile** eine sinnvolle Produktentscheidung. Ein einmaliger **Abschlusstext** nach den Summen ist ein anderes Element. Die Erwartung des Nutzers entspricht dieser Unterscheidung; eine allgemeine umsatzsteuerrechtliche Pflicht zur Wiederholung sämtlicher Angaben auf jeder Seite folgt daraus jedoch nicht.

## Umsatzsteuerrecht: Inhalt der Rechnung, nicht Pflicht zur Wiederholung je Seite

§ 14 Abs. 4 UStG nennt Pflichtangaben der Rechnung, darunter Namen und Anschriften, Steuernummer oder Umsatzsteuer-ID, Rechnungsnummer sowie Entgelt und Steuer. Die Vorschrift legt keine wiederkehrende Seitenfußzeile fest. Bankverbindungen gehören nicht zu ihrer Aufzählung. Dies ist eine Aussage zum genannten umsatzsteuerrechtlichen Pflichtenkatalog, keine umfassende Prüfung aller rechtsformspezifischen Geschäftspapierpflichten. [§ 14 UStG](https://www.gesetze-im-internet.de/ustg_1980/__14.html)

§ 31 Abs. 1 UStDV erlaubt sogar eine Rechnung aus mehreren Dokumenten, deren Angaben sich zusammen ergeben. Dafür müssen die Dokumente entsprechend bezeichnet und die Angaben leicht und eindeutig prüfbar sein. **Einordnung:** Die Bestimmung spricht für die Rechnung als zusammenhängende Gesamtheit; eine Verpflichtung, Firmen-, Steuer- und Bankdaten auf jedem Blatt zu wiederholen, lässt sich aus diesen beiden Vorschriften nicht ableiten. [§ 31 UStDV](https://www.gesetze-im-internet.de/ustdv_1980/__31.html), [erfolgreich abgerufene amtliche Gesamtausgabe, § 31](https://www.gesetze-im-internet.de/ustdv_1980/BJNR023590979.html)

## Dokumentgestaltung und Produktbeispiele

- Invoice Office unterscheidet ausdrücklich die Firmenfußzeile als Seitenelement vom Schlussblock mit Gruß, Zahlungsanweisung oder Signatur. Die Firmenfußzeile wird auf jeder Seite wiederholt; das Produkt empfiehlt eine kompakte Gestaltung, damit Platz für Positionen bleibt. Der vollständige Herstellertext war über den Suchindex zugänglich; der direkte Abruf lieferte einen Cache-Fehler. [Invoice Office: Set footers and signature](https://www.invoiceoffice.com/support/set-footers-and-signature)
- Eine zusätzlich direkt abrufbare Herstellerquelle belegt genau dieselbe Unterscheidung: Ajera beschreibt den einmaligen Footer-Text auf der letzten Rechnungsseite und erklärt auf Seite 6: „The page footer prints on every page.“ Seitenzahlen sind separat konfigurierbar. [Ajera: Client invoice components, Seite 6](https://learningcenter.axium.com/DocsAndLessons/quickref_ClientInvoiceComponents.pdf#page=6)
- Lexware beschreibt Firmen-/Bankdaten am unteren Belegbereich sowie Seitenzahlen in der Fußzeile oder im Inhalt und wiederholte Belegkennung auf Folgeseiten. Das belegt übliche Gestaltungsoptionen, keine universelle Norm. [Lexware: Drucklayout bearbeiten](https://help.lexware.de/de-form/articles/548055-wie-bearbeite-ich-mein-drucklayout)
- Das W3C-Seitenmodell trennt fließenden Inhalt von Seitenrändern für laufende Kopf-/Fußzeilen und Seitenzähler. Die zitierte CSS-Paged-Media-Spezifikation ist ein Working Draft vom 14. September 2023. Sie beschreibt das Konzept; sie beweist weder Unterstützung durch WKWebView noch durch den eigenen PDFMercury-Renderer. „Ganz unten“ bedeutet im druckbaren Fußbereich mit Sicherheitsrand, nicht bis an die Papierkante. [W3C CSS Paged Media, § 2 und § 5](https://www.w3.org/TR/css-page-3/#margin-boxes)

Es wird keine konkrete DIN-5008-Regel behauptet: Dafür wurde kein zugänglicher Primärtext geprüft.

## Tatsächlicher lokaler Implementierungsstand

Die folgenden Befunde stammen aus der parallelen lokalen Codeprüfung des Hauptagenten:

- Classic setzt nach den Summen, Steuerhinweisen und `footerText` genau ein `<footer>` an das Ende des HTML-Inhalts. [template_classic.html:45](/Users/bastian/Developer/Earnie/invoice-kit/Sources/InvoiceKit/Resources/Templates/Classic/template_classic.html:45)
- Der Footer ist ein normal mitfließendes Grid mit `margin-top: 2mm` und `break-inside: avoid`. Es gibt keine Bindung an die untere Seitenkante. Der Summenblock besitzt dagegen keinen entsprechenden Schutz gegen Seitenumbruch. [template_classic.css:124](/Users/bastian/Developer/Earnie/invoice-kit/Sources/InvoiceKit/Resources/Templates/Classic/template_classic.css:124), [Footer-Stil:155](/Users/bastian/Developer/Earnie/invoice-kit/Sources/InvoiceKit/Resources/Templates/Classic/template_classic.css:155)
- PDFMercury zerlegt den Inhalt in Seiten und zeichnet optional wiederholte Tabellenköpfe. Eine laufende Fußzeile ist in diesem Zusammensetzen nicht enthalten. [RenderEngine.swift:40](/Users/bastian/Developer/OpenSource/PDFMercury/Sources/PDFMercury/RenderEngine.swift:40), [Zusammensetzen:295](/Users/bastian/Developer/OpenSource/PDFMercury/Sources/PDFMercury/RenderEngine.swift:295)
- Die Dokumentation nennt laufende Kopf-/Fußzeilen und Seitenzähler ausdrücklich außerhalb des unterstützten Umfangs. [documentation.md:47](/Users/bastian/Developer/OpenSource/PDFMercury/Doc/documentation.md:47)

Das Verhalten ist somit durch die aktuelle Implementierung erklärbar. Aus dem Code allein lässt sich keine bewusst beschlossene Produktanforderung ableiten. Im Nutzer-Screenshot steht zusätzlich der Gesamtbetrag von 428,40 € auf der nächsten Seite, getrennt von Zwischensumme und Umsatzsteuer. Das ist eine eigenständige Umbruchschwäche.

## Empfehlung für eine spätere Umsetzung

1. Firmen-, Kontakt-, Steuer- und Bankdaten als kompakte Seitenfußzeile wiederholen, auch auf einer nur teilweise gefüllten letzten Seite.
2. Ihre Höhe vor dem Seitenumbruch bestimmen und auf jeder Seite Platz inklusive Abstand und druckbarem unteren Rand reservieren. Danach im reservierten Bereich zeichnen; keine über den Inhalt gelegte Fußzeile.
3. Rechnungsnummer und „Seite X von Y“ zur Zuordnung ergänzen.
4. Freien Abschlusstext, individuelle Zahlungshinweise und Gesamtsumme einmal am Rechnungsende lassen. Zwischensumme, Steuer und Gesamtbetrag zusammenhalten, sofern der Block auf eine Seite passt.

Dies sind Gestaltungsempfehlungen aus der Recherche und dem beobachteten Fehlerbild, keine bereits implementierten Fähigkeiten oder gesetzlichen Pflichtvorgaben.
