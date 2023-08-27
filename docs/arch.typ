#import "/book.typ": book-page
#import "/templates/page.typ": page-width, is-dark-theme
#import "@preview/fontawesome:0.1.0": *
#import "@preview/colorful-boxes:1.1.0": *
#import "@preview/commute:0.1.0": node, arr, commutative-diagram

#show: book-page.with(title: "Typst-Preview Architecture")
#show link: underline

= Architecture

Typst preview consists of two parts:
1. The first one is the typst preview server, which watches events, recompiles the document and sends it to client. This part is written in rust and is the core of typst preview.
2. The second one is the typst preview client, which is a web client that renders the preview pages. This part is written in typescript and wasm.

These two parts communicate with each other through websockets. The server sends the compiled document to the client, and the client renders it.

== Rust Part of Typst Preview

=== Actors

The architecture of typst preview mainly follows the actor model. To be more specific, there are four actors in the system:

1. _Typst Actor_: The typst actor is the main actor of the system. It is responsible for watching the file system, compiling the document and resolving cross jump requests. Basically everything related to typst's `World` is handled by this actor. There is exactly one typst actor in the system.
3. _Editor Actor_: This actor listens to the events from the editor. It is responsible for sending the events to the typst actor. There is exactly one editor actor in the system. When the editor is closed, the editor actor will shutdown the whole program otherwise the program will keep running, resulting in process leak.
2. _Render Actor_: The render actor is responsible for rendering the document. It receives the compiled document from the typst actor and renders it. There can be multiple render actors in the system. The number of render actors is equal to the number of clients connected to the server.
4. _Webview Actor_: Webview actor is responsible for communicating with the webview client. It receives the events from the webview client and sends them to relevant actors. The number of webview actors is equal to the number of render actors.

We can see that the first two actors are CPU heavy, while the last two actors are IO heavy. Therefore we use different runtimes for them. For each CPU heavy actor, we create a thread and run the actor on it. For each IO heavy actor, we create a tokio task and run the actor on it. These actors can send messages to each other using `tokio::sync::mpsc`.

A dedicated thread for the first two actor is necessary because typst use #link("https://github.com/typst/comemo")[comemo] under the hood, which use thread local storage to cache intermediate results. If we run the first two actors on tokio tasks, the thread local storage will not work, resulting in unstable performance.

=== Renderer

To achieve incremental and high performance rendering, we use #link("https://github.com/Myriad-Dreamin/typst.ts")[typst.ts] to render docuement. To be specific, we use the `IncrementalSvgExporter`. The `IncrementalSvgExporter` will only output the changed part of the document. The result is serialized to using #link("https://github.com/rkyv/rkyv")[rkyv]. The serialized result is then sent to the client.

== Client Part of Typst Preview

The client part of typst preview is written in typescript and wasm. It is responsible for rendering the document. It receives the serialized document from the server, deserializes it using rkyv and apply the changes to the VDOM to get the latest document. This is done by #link("https://github.com/Myriad-Dreamin/typst.ts/tree/main/packages/renderer")[typst-ts-renderer].

For optimization, we maintains the visible rectangle of the document in the client. When the document is updated, we only re-render the visible part of the document.