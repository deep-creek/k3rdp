// Qt6 Widgets sample for the k3rdp stack.
//
// It renders into the shared X11 display (DISPLAY points at the x11rdp pod over
// TCP) as a single borderless fullscreen window, labeled with the screen's
// geometry and DPI. A live clock proves the event loop is running, and a
// continuously-updating readout shows the current mouse position.
//
// Swap this out for your own Qt application; the deployment only requires that
// the binary honors DISPLAY / QT_QPA_PLATFORM=xcb.

#include <QApplication>
#include <QScreen>
#include <QCursor>
#include <QLabel>
#include <QVBoxLayout>
#include <QWidget>
#include <QTimer>
#include <QTime>
#include <QFont>
#include <QString>
#include <QPoint>
#include <QDebug>

// Build the panel: a heading, the screen info, a live clock, and a mouse-position
// label (returned via `mouseLabelOut` so the caller can update it from a timer).
static QWidget *makePanel(const QString &title, const QString &info, QLabel **mouseLabelOut)
{
    auto *w = new QWidget;
    w->setWindowTitle("k3rdp — " + title);

    auto *layout = new QVBoxLayout(w);
    layout->setContentsMargins(48, 48, 48, 48);
    layout->setSpacing(24);

    auto *heading = new QLabel(title);
    QFont hf = heading->font();
    hf.setPointSize(24);
    hf.setBold(true);
    heading->setFont(hf);
    heading->setAlignment(Qt::AlignCenter);

    auto *detail = new QLabel(info);
    detail->setAlignment(Qt::AlignCenter);
    detail->setTextInteractionFlags(Qt::TextSelectableByMouse);

    auto *clock = new QLabel;
    QFont cf = clock->font();
    cf.setPointSize(40);
    clock->setFont(cf);
    clock->setAlignment(Qt::AlignCenter);

    auto *mouse = new QLabel("Mouse: —");
    QFont mf = mouse->font();
    mf.setPointSize(16);
    mouse->setFont(mf);
    mouse->setAlignment(Qt::AlignCenter);

    auto *timer = new QTimer(w);
    QObject::connect(timer, &QTimer::timeout, clock, [clock]() {
        clock->setText(QTime::currentTime().toString("HH:mm:ss"));
    });
    timer->start(1000);
    clock->setText(QTime::currentTime().toString("HH:mm:ss"));

    layout->addStretch();
    layout->addWidget(heading);
    layout->addWidget(detail);
    layout->addWidget(clock);
    layout->addWidget(mouse);
    layout->addStretch();

    if (mouseLabelOut)
        *mouseLabelOut = mouse;
    return w;
}

static QString screenInfo(const QScreen *s)
{
    const QRect g = s->geometry();
    return QString("name: %1\n%2 x %3  at  (%4, %5)\nlogical DPI: %6\nphysical DPI: %7")
        .arg(s->name())
        .arg(g.width()).arg(g.height())
        .arg(g.x()).arg(g.y())
        .arg(qRound(s->logicalDotsPerInch()))
        .arg(qRound(s->physicalDotsPerInch()));
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);

    QScreen *s = QGuiApplication::primaryScreen();
    qInfo().noquote() << "[qtapp] screen:" << s->name()
                      << s->geometry() << "phys-dpi" << s->physicalDotsPerInch();

    QLabel *mouseLabel = nullptr;
    QWidget *w = makePanel("Qt over X11/RDP", screenInfo(s), &mouseLabel);
    // Borderless fullscreen kiosk window (IceWM honors _NET_WM_STATE_FULLSCREEN).
    w->showFullScreen();

    // Continuously show the mouse position. Polling QCursor::pos() tracks the X
    // pointer without needing focus or mouse-tracking on the widget.
    auto *mouseTimer = new QTimer(&app);
    QObject::connect(mouseTimer, &QTimer::timeout, &app, [mouseLabel]() {
        const QPoint p = QCursor::pos();
        QScreen *cur = QGuiApplication::screenAt(p);
        QString text;
        if (cur) {
            const QPoint local = p - cur->geometry().topLeft();
            text = QString("Mouse: global (%1, %2)\non %3: local (%4, %5)")
                       .arg(p.x()).arg(p.y())
                       .arg(cur->name()).arg(local.x()).arg(local.y());
        } else {
            text = QString("Mouse: global (%1, %2)").arg(p.x()).arg(p.y());
        }
        mouseLabel->setText(text);
    });
    mouseTimer->start(30);   // ~33 Hz — smooth, continuous updates

    return app.exec();
}
