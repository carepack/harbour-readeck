/*
 * Gecko/embedlite frame script (runs in the web content process, not the
 * QML/UI process -- see CaptureContentPage.qml, which loads this via
 * WebView.loadFrameScript() and talks to it with
 * sendAsyncMessage()/onRecvAsyncMessage()).
 *
 * This is the local equivalent of what iOS Safari Share Extensions get
 * for free via NSExtensionJavaScriptPreprocessingFile: reading the
 * live, currently-rendered DOM (including anything behind a login the
 * user is signed into in this embedded browser) rather than whatever a
 * server-side fetch of the bare URL would see.
 *
 * addMessageListener/sendAsyncMessage are globals injected into this
 * script's scope by the message manager; "content" is the loaded page's
 * window object.
 */
addMessageListener("readeck:extractContent", function () {
    var doc = content.document;
    sendAsyncMessage("readeck:contentExtracted", {
        url: doc.URL,
        title: doc.title,
        html: doc.documentElement.outerHTML
    });
});
