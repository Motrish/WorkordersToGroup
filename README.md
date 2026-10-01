# WorkordersToGroup 1.0.0

WorkordersToGroup erweitert OTOBO ITSM Change Management um Gruppenzuweisungen für Arbeitsaufträge. Agenten können Aufträge ihrer berechtigten Gruppen übernehmen; Change Manager und Administratoren können sie Gruppenmitgliedern zuweisen.

Repository: [Motrish/WorkordersToGroup](https://github.com/Motrish/WorkordersToGroup)

## Funktionen

- Der native Zuweisungsdialog bietet aktive Agenten und freigegebene Gruppen in einer Auswahl. Auch Agenten, die als abwesend markiert sind, bleiben auswählbar.
- Eine Agentenzuweisung aktualisiert die native WorkOrderAgentID und entfernt eine vorhandene Gruppenzuordnung. Eine Gruppenzuweisung leert die native Agentenzuweisung und speichert die Gruppe samt Audit-Eintrag. Nicht zugewiesen entfernt beide Ziele.
- Das Gruppensymbol in der Agenten-Kopfleiste zeigt die Zahl übernehmbarer Gruppenaufträge. Bei mindestens einem passenden Auftrag blinkt das Symbol rot. Ein Klick öffnet die Teamübersicht.
- Die Teamübersicht trennt Arbeitsauftrag und Anweisung in eigene Spalten. Spalten lassen sich sortieren und über Lupensymbole live filtern. Statusnamen werden übersetzt und erhalten einen Punkt in der konfigurierten Statusfarbe.
- Berechtigte Agenten können Aufträge in der Übersicht oder im Arbeitsauftrag öffnen und übernehmen. Change Manager und Administratoren können einen aktiven RW-Gruppenagenten zuweisen.
- Eine Admin-Seite unterstützt die Korrektur von Zuordnungen, Audit-Prüfungen und die Vorschau sowie Übernahme bestehender Change-Automation-Zuordnungen.
- Serverseitige Prüfungen, CSRF-Schutz, konkurrierende Übernahmen und Audit-Einträge sichern die Änderungen ab. Die Zuordnungen werden transaktional mit dem nativen Arbeitsauftrag verwaltet.

## Voraussetzungen

- OTOBO 11.0.13 innerhalb der 11.0-Reihe
- ITSMChangeManagement 11.0.3

Die Kompatibilität wurde anhand der Quellstände dieser OTOBO- und ITSM-Releases entwickelt und geprüft. Lokale Paket- und Testsuite-Prüfungen sind dokumentiert in docs/compatibility.md.

## Installation und Konfiguration

1. Installieren Sie das OPM-Paket WorkordersToGroup 1.0.0 über den Paketmanager.
2. Öffnen Sie SysConfig > Core::ITSMWorkOrder und tragen Sie unter WorkordersToGroup::AssignableGroups die IDs der Gruppen ein, die Arbeitsaufträge erhalten dürfen. Die Einstellung ist standardmäßig leer.
3. Erstellen Sie SysConfig neu und leeren Sie den OTOBO-Cache nach dem Installationsverfahren Ihrer Instanz.
4. Prüfen Sie die Gruppenrechte und die native Zuweisung mit Testkonten, bevor Sie die Funktion produktiv freigeben.

Für die Integration mit CustomChangeAutomation 0.3.7 muss WorkordersToGroup zuerst installiert und konfiguriert werden. Jede Gruppe, die CustomChangeAutomation für einen Auftrag verwendet, muss in der Allowlist stehen. Beim Upgrade deaktiviert CustomChangeAutomation seine doppelten Berechtigungs-Aliase und das alte Team-Menü; dessen bisherige Route bleibt als Weiterleitung erhalten.

## Betrieb

Die Agentenübersicht zeigt nur offene, gruppenzugeordnete Arbeitsaufträge, für die der angemeldete Agent effektive RW-Rechte hat. Die Anzeige verwendet Seiten-Cursor, Sortierung und Filterung. Das Toolbar-Zählwerk wird agentenweit eingebunden; schlägt seine Berechtigungs- oder Datenbankabfrage fehl, wird der Fehler protokolliert und die Seite weiterhin mit Zähler 0 geladen.

Die Gruppenzuordnung beschränkt sich auf aktive Gruppen in WorkordersToGroup::AssignableGroups. Eine Gruppenübernahme setzt den nativen Agenten und die Gruppenzuordnung gemeinsam. Gleichzeitige Übernahmen desselben Auftrags werden serialisiert; der zweite Request erhält einen Konflikt statt einer doppelten Zuordnung.

Vor der Migration vorhandener Automationszuordnungen erstellen Sie ein Backup. Nutzen Sie auf der Admin-Seite zuerst die Vorschau, prüfen Sie Konflikte und ungültige Zeilen und führen Sie die Migration anschließend aus. Die Migration ist idempotent; Fehler und Teilfortschritte werden zeilenweise ausgegeben.

## API für Integrationen

Integrationen schreiben nicht direkt in die WorkordersToGroup-Tabellen, sondern verwenden den Zuweisungsdienst:

~~~perl
my $Result = $Kernel::OM->Get(
    'Kernel::System::WorkordersToGroup::Assignment'
)->Assign(
    WorkOrderID   => $WorkOrderID,
    ChangeID      => $ChangeID,
    GroupID       => $GroupID,
    UserID        => $ActorID,
    SourcePackage => 'CustomChangeAutomation',
    SourceKey     => $InstanceID . ':' . $Slot,
);
if (!$Result || !$Result->{Success}) {
    my $Code = $Result ? ($Result->{Code} || 'UnknownError') : 'NoResult';
    die $Code;
}
~~~

Assign ist für dieselbe Arbeitsauftrags- und Gruppenzuordnung idempotent und lehnt widersprüchliche Zuordnungen ab. Es akzeptiert nur Gruppen aus der SysConfig-Allowlist. Änderungen am nativen Arbeitsauftrag benötigen eine eigene äußere Datenbanktransaktion, damit OTOBO-Ereignisse erst nach dem Commit ausgelöst werden. Bei einer bereits offenen Transaktion eines aufrufenden Moduls schlägt die Mutation mit OUTER_TRANSACTION_ACTIVE fehl. Lesezugriffe bleiben möglich.

Weitere Operationen umfassen SetTarget für die native Agenten-, Gruppen- oder Nicht-zugewiesen-Auswahl sowie Claim, ReassignAgent, Release, ChangeGroup und Remove.

## Upgrade und Deinstallation

Vor einem Upgrade sichern Sie Datenbank und Paketstand und prüfen aktive Zuordnungen. Die Datenbanktabellen bleiben bei einer Deinstallation absichtlich erhalten. Entfernen Sie die Durchsetzung der Gruppenzuordnung erst, wenn aktive verwaltete Aufträge migriert oder anderweitig bereinigt wurden.

## Prüfungen und bekannte Grenze

Lokale Tests, Perl- und JavaScript-Syntax, XML-Dateien und der OPM-Paketinhalt werden für den Release geprüft. Eine vollständige Installation mit Datenbankmigration und Browserprüfung muss in einer passenden OTOBO-Testinstanz erfolgen; diese Laufzeitumgebung ist im vorliegenden Workspace nicht eingerichtet. Die konkreten Integrationsfälle stehen in docs/compatibility.md.

## Lizenz

GNU General Public License, Version 3 vom 29. Juni 2007.
