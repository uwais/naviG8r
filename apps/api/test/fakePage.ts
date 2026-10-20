/**
 * Just enough of a browser to run a server-built page's inline script in node:vm, press its buttons and see what it
 * asks the server, with every request going to a real test server. No layout, CSS or event bubbling: a test that
 * needs those belongs in Playwright.
 */
import vm from "node:vm";

type Handler = ((event: { preventDefault(): void }) => unknown) | null;

export class FakeElement {
  children: FakeElement[] = [];
  parent: FakeElement | null = null;
  attributes = new Map<string, string>();
  hidden = false;
  disabled = false;
  checked = false;
  required = false;
  open = false;
  id = "";
  className = "";
  value = "";
  type = "";
  name = "";
  placeholder = "";
  step = "";
  htmlFor = "";
  onclick: Handler = null;
  onsubmit: Handler = null;
  oninput: Handler = null;
  onchange: Handler = null;
  private ownText = "";
  readonly tagName: string;
  private readonly page: FakePage;
  constructor(tagName: string, page: FakePage) {
    this.tagName = tagName;
    this.page = page;
  }

  get textContent(): string {
    return this.ownText + this.children.map((child) => child.textContent).join("");
  }
  set textContent(value: string) {
    this.replaceChildren();
    this.ownText = String(value);
  }
  append(...nodes: (FakeElement | string)[]): void {
    for (const node of nodes) {
      const child = typeof node === "string" ? this.page.text(node) : node;
      child.remove();
      child.parent = this;
      this.children.push(child);
    }
  }
  replaceChildren(...nodes: (FakeElement | string)[]): void {
    for (const child of this.children) child.parent = null;
    this.children = [];
    this.ownText = "";
    this.append(...nodes);
  }
  remove(): void {
    if (this.parent) this.parent.children = this.parent.children.filter((child) => child !== this);
    this.parent = null;
  }
  get isConnected(): boolean {
    let node: FakeElement = this;
    while (node.parent) node = node.parent;
    return node === this.page.body;
  }
  readonly dataset: Record<string, string> = {};
  /** As in the browser, the hidden and disabled attributes switch the matching properties on. */
  setAttribute(key: string, value: unknown): void {
    this.attributes.set(key, String(value));
    if (key === "id") this.id = String(value);
    if (key === "hidden") this.hidden = true;
    if (key === "disabled") this.disabled = true;
  }
  removeAttribute(key: string): void {
    this.attributes.delete(key);
  }
  getAttribute(key: string): string | null {
    return this.attributes.get(key) ?? null;
  }
  addEventListener(): void {}
  focus(): void {
    this.page.focused = this;
  }
  scrollIntoView(): void {}
  querySelectorAll(tagName: string): FakeElement[] {
    return this.descendants().filter((node) => node.tagName === tagName);
  }
  descendants(): FakeElement[] {
    return this.children.flatMap((child) => [child, ...child.descendants()]);
  }
  /** A form's controls, as form.elements gives them. */
  get elements(): FakeElement[] {
    return this.descendants().filter((node) => ["input", "select", "textarea", "button"].includes(node.tagName));
  }
  /** Visible means it and every ancestor are not hidden, the way [hidden] works in the browser. */
  get visible(): boolean {
    for (let node: FakeElement | null = this; node; node = node.parent) if (node.hidden) return false;
    return true;
  }
}

export class FakePage {
  readonly body: FakeElement = new FakeElement("body", this);
  readonly requests: { method: string; path: string }[] = [];
  readonly session = new Map<string, string>();
  focused: FakeElement | null = null;
  nativeDialogs = 0;
  private inFlight = 0;
  private context: vm.Context | null = null;

  private readonly base: string;
  constructor(base: string) {
    this.base = base;
  }

  text(value: string): FakeElement {
    const node = new FakeElement("#text", this);
    node.textContent = value;
    return node;
  }

  /** Elements the markup would have defined are made on first use and attached to the page. */
  byId(id: string): FakeElement {
    const found = this.body.descendants().find((node) => node.id === id);
    if (found) return found;
    const made = new FakeElement("div", this);
    made.id = id;
    this.body.append(made);
    return made;
  }

  /** Later scripts share the first one's globals, as scripts on one page do. Returns the script's last value. */
  run(script: string): unknown {
    this.context ??= this.makeContext();
    return vm.runInContext(script, this.context);
  }

  private makeContext(): vm.Context {
    const page = this;
    return vm.createContext({
      // CSS selectors are not supported: they find nothing, which is what a page with no such markup would find.
      document: { getElementById: (id: string) => page.byId(id), createElement: (tag: string) => new FakeElement(tag, page), querySelector: () => null, querySelectorAll: () => [] },
      AbortSignal,
      sessionStorage: {
        getItem: (key: string) => page.session.get(key) ?? null,
        setItem: (key: string, value: string) => page.session.set(key, String(value)),
        removeItem: (key: string) => page.session.delete(key),
        clear: () => page.session.clear(),
      },
      fetch: (path: string, init: { method?: string } = {}) => {
        page.requests.push({ method: init.method ?? "GET", path });
        page.inFlight += 1;
        return fetch(page.base + path, init as RequestInit).finally(() => { page.inFlight -= 1; });
      },
      Option: function (this: unknown, label: string, value: string) {
        const option = new FakeElement("option", page);
        option.textContent = label;
        option.value = value;
        return option;
      },
      FormData: function (form: FakeElement) {
        return form.descendants().filter((node) => node.name).map((node) => [node.name, node.value]);
      },
      confirm: () => { page.nativeDialogs += 1; return true; },
      alert: () => { page.nativeDialogs += 1; },
      location: { reload() {} },
      URLSearchParams,
      setTimeout,
      clearTimeout,
      setInterval,
      clearInterval,
    });
  }

  /** Waits until no request is in flight and the handlers that follow one have run. */
  async settle(): Promise<void> {
    for (let quietTurns = 0; quietTurns < 5; ) {
      await new Promise((resolve) => setTimeout(resolve, 5));
      quietTurns = this.inFlight === 0 ? quietTurns + 1 : 0;
    }
  }

  /** A click runs the button's handler, then submits its form unless it is a type="button" button. */
  async click(button: FakeElement): Promise<void> {
    if (button.disabled || !button.visible) throw new Error("cannot click a disabled or hidden button: " + button.textContent);
    const event = { preventDefault() {} };
    await button.onclick?.(event);
    if (button.tagName === "button" && button.type !== "button") {
      let form = button.parent;
      while (form && form.tagName !== "form") form = form.parent;
      await form?.onsubmit?.(event);
    }
    await this.settle();
  }

  visibleButton(name: string, within: FakeElement = this.body): FakeElement | undefined {
    return within.querySelectorAll("button").find((button) => button.textContent === name && button.visible);
  }

  releaseRequests(): { method: string; path: string }[] {
    return this.requests.filter((request) => request.method === "POST" && request.path.endsWith("/release"));
  }
}

export function inlineScript(html: string): string {
  return html.split("<script>")[1]?.split("</script>")[0] ?? "";
}
