(function () {
  'use strict';

  const API_BASE_URL =
    (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  // Deliberately not defaulted to true: an operator must explicitly flip
  // this in config.js after confirming API_BASE_URL is reachable and
  // correct (see the instructions in config.js). This turns an unverified
  // guess into a hard stop instead of a silent failure in production.
  const API_BASE_URL_VERIFIED =
    !!(window.FNF_CONFIG && window.FNF_CONFIG.VERIFIED === true);

  const ASSET_HOST = API_BASE_URL.endsWith('/api')
    ? API_BASE_URL.slice(0, -4)
    : API_BASE_URL;

  const els = {
    loadingState: document.getElementById('loadingState'),
    loadingSlowHint: document.getElementById('loadingSlowHint'),
    errorState: document.getElementById('errorState'),
    errorTitle: document.getElementById('errorTitle'),
    errorMessage: document.getElementById('errorMessage'),
    retryBtn: document.getElementById('retryBtn'),

    successState: document.getElementById('successState'),
    successHeading: document.getElementById('successHeading'),
    successSubtext: document.getElementById('successSubtext'),
    successTable: document.getElementById('successTable'),
    successOrderNumber: document.getElementById('successOrderNumber'),
    successTotal: document.getElementById('successTotal'),
    successItems: document.getElementById('successItems'),
    successStatus: document.getElementById('successStatus'),
    successStatusText: document.getElementById('successStatusText'),
    doneBtn: document.getElementById('doneBtn'),
    feedbackBox: document.getElementById('feedbackBox'),
    feedbackStars: document.getElementById('feedbackStars'),
    feedbackComment: document.getElementById('feedbackComment'),
    submitFeedbackBtn: document.getElementById('submitFeedbackBtn'),
    feedbackMessage: document.getElementById('feedbackMessage'),

    app: document.getElementById('app'),
    tableBadge: document.getElementById('tableBadge'),

    searchInput: document.getElementById('searchInput'),
    clearSearch: document.getElementById('clearSearch'),

    categoryChips: document.getElementById('categoryChips'),
    productList: document.getElementById('productList'),

    searchEmpty: document.getElementById('searchEmpty'),
    clearSearchBtn: document.getElementById('clearSearchBtn'),

    cartBar: document.getElementById('cartBar'),
    cartCount: document.getElementById('cartCount'),
    cartBarTotal: document.getElementById('cartBarTotal'),

    cartOverlay: document.getElementById('cartOverlay'),
    closeCart: document.getElementById('closeCart'),

    cartLines: document.getElementById('cartLines'),
    cartItemCount: document.getElementById('cartItemCount'),
    cartTotal: document.getElementById('cartTotal'),

    customerName: document.getElementById('customerName'),
    customerPhone: document.getElementById('customerPhone'),
    orderNote: document.getElementById('orderNote'),
    onlinePaymentOption: document.getElementById('onlinePaymentOption'),
    payUpiBtn: document.getElementById('payUpiBtn'),
    upiHelpText: document.getElementById('upiHelpText'),

    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),

    upiPendingState: document.getElementById('upiPendingState'),
    upiPendingHeading: document.getElementById('upiPendingHeading'),
    upiPendingTable: document.getElementById('upiPendingTable'),
    upiPendingOrderNumber: document.getElementById('upiPendingOrderNumber'),
    upiPendingTotal: document.getElementById('upiPendingTotal'),
    upiReopenBtn: document.getElementById('upiReopenBtn'),
    upiPendingReferenceInput: document.getElementById('upiPendingReferenceInput'),
    upiPendingError: document.getElementById('upiPendingError'),
    upiSubmitReferenceBtn: document.getElementById('upiSubmitReferenceBtn'),
    upiPendingStatusCard: document.getElementById('upiPendingStatusCard'),
    upiPendingStatusText: document.getElementById('upiPendingStatusText'),
    upiCancelBtn: document.getElementById('upiCancelBtn'),
  };

  const state = {
    paymentOptions: { onlineUpi: false, upiId: '', cafeName: 'FAST N FRESH CAFE' },
    tableNumber: null,
    tableName: null,

    categories: [],
    items: [],

    activeCategory: 'all',
    searchQuery: '',

    cart: new Map(),

    loading: false,

    // Generated the first time "Place Order" is attempted for the current
    // cart, and reused on retries (e.g. a network blip or a slow response
    // the customer taps through again) so a resend can't create a second
    // order. Cleared whenever the cart itself changes or an order
    // succeeds, since that means a genuinely new order is being started.
    clientRequestId: null,
    tracking: { orderId: null, token: null, timer: null, status: null },
    feedbackRating: 0,
    // Holds the order created the moment the customer taps "Pay with UPI".
    // The order exists in the cafe's system immediately (staff can see an
    // unpaid QR order), but paymentStatus stays 'payment_initiated' until a
    // human verifies the money arrived. Shape:
    // { orderId, token, orderNumber, tableName, tableNumber, total, items, upiUrl, referenceSubmitted, pollTimer }
    upiOrder: null,
  };

  function generateRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    // Fallback UUID v4 for browsers/contexts without crypto.randomUUID
    // (e.g. non-HTTPS local development).
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function invalidateClientRequestId() {
    state.clientRequestId = null;
  }

  /* =========================================================
     HELPERS
     ========================================================= */

  function formatMoney(value) {
    return '₹' + Number(value || 0).toLocaleString('en-IN', {
      maximumFractionDigits: 2,
    });
  }

  let slowHintTimer = null;

  function startSlowHintTimer() {
    clearSlowHintTimer();
    if (!els.loadingSlowHint) return;
    slowHintTimer = window.setTimeout(() => {
      els.loadingSlowHint.classList.remove('hidden');
    }, 6000);
  }

  function clearSlowHintTimer() {
    if (slowHintTimer) {
      window.clearTimeout(slowHintTimer);
      slowHintTimer = null;
    }
    if (els.loadingSlowHint) els.loadingSlowHint.classList.add('hidden');
  }

  function showState(name) {
    if (name !== 'loadingState') {
      clearSlowHintTimer();
    }

    [
      'loadingState',
      'errorState',
      'successState',
      'upiPendingState',
      'app',
    ].forEach((key) => {
      if (!els[key]) return;

      els[key].classList.toggle(
        'hidden',
        key !== name
      );
    });
  }

  function showFatalError(title, message) {
    els.errorTitle.textContent = title;
    els.errorMessage.textContent = message;
    showState('errorState');
  }

  async function apiRequest(path, options = {}) {
    if (
      !API_BASE_URL ||
      API_BASE_URL.includes('your-deployed-api-domain.com')
    ) {
      throw new Error(
        'Cafe menu is not configured correctly.'
      );
    }

    if (!API_BASE_URL_VERIFIED) {
      throw new Error(
        'This menu has not been confirmed to be connected to the ' +
        'right server yet. Please ask staff, or see the instructions ' +
        'in config.js.'
      );
    }

    let response;
    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 15000);

    try {
      response = await fetch(
        API_BASE_URL + path,
        {
          headers: {
            'Content-Type': 'application/json',
          },
          ...options,
          signal: controller.signal,
        }
      );
    } catch (error) {
      if (error?.name === 'AbortError') {
        throw new Error(
          'Cafe server took too long to respond. Please try again.'
        );
      }
      throw new Error(
        'Network error. Please check your internet connection.'
      );
    } finally {
      window.clearTimeout(timeoutId);
    }

    let body;

    try {
      body = await response.json();
    } catch {
      throw new Error(
        'Cafe server returned an invalid response.'
      );
    }

    if (!response.ok || !body.success) {
      throw new Error(
        body?.message ||
        'Something went wrong. Please try again.'
      );
    }

    return body;
  }

  function getTableNumberFromUrl() {
    const params = new URLSearchParams(
      window.location.search
    );

    const raw = params.get('table');

    const number = Number(raw);

    if (
      !raw ||
      !Number.isInteger(number) ||
      number < 1
    ) {
      return null;
    }

    return number;
  }

  /* =========================================================
     RETURNING CUSTOMER — RESTORE A PENDING ORDER
     ========================================================= */

  const PENDING_ORDER_KEY = 'fnf_last_order';
  const PENDING_UPI_KEY = 'fnf_pending_upi_payment';

  function clearPendingOrder() {
    try {
      localStorage.removeItem(PENDING_ORDER_KEY);
    } catch (_) {}
  }

  function readPendingOrder() {
    try {
      const raw = localStorage.getItem(PENDING_ORDER_KEY);
      if (!raw) return null;

      const parsed = JSON.parse(raw);

      if (!parsed || !parsed.orderId || !parsed.token) {
        return null;
      }

      return parsed;
    } catch (_) {
      return null;
    }
  }

  function renderOrderItems(items) {
    if (!els.successItems) return;

    els.successItems.innerHTML = '';

    (items || []).forEach((item) => {
      const row = document.createElement('div');
      row.className = 'success-item-row';

      const nameWrap = document.createElement('span');
      nameWrap.className = 'success-item-name';

      const qty = document.createElement('span');
      qty.className = 'success-item-qty';
      qty.textContent = `${item.quantity}× `;

      nameWrap.appendChild(qty);
      nameWrap.appendChild(
        document.createTextNode(item.name || '')
      );

      const price = document.createElement('span');
      price.className = 'success-item-price';

      const lineTotal =
        item.total != null
          ? item.total
          : (item.price || 0) * (item.quantity || 1);

      price.textContent = formatMoney(lineTotal);

      row.appendChild(nameWrap);
      row.appendChild(price);

      els.successItems.appendChild(row);
    });
  }

  // If the customer closes the tab (or the page reloads) after ordering,
  // this restores their order tracking view instead of dropping them back
  // into an empty menu with no memory of what they ordered.
  async function tryRestorePendingOrder() {
    const pending = readPendingOrder();
    if (!pending) return false;

    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(pending.orderId)}/status?token=${encodeURIComponent(pending.token)}`
      );

      const data = response.data || {};

      if (data.status === 'voided') {
        clearPendingOrder();
        return false;
      }

      if (els.successHeading) {
        els.successHeading.textContent = 'Welcome back!';
      }

      if (els.successSubtext) {
        els.successSubtext.textContent =
          "Here's your order from this table.";
      }

      els.successTable.textContent =
        data.tableName || `Table ${data.tableNumber}`;

      els.successOrderNumber.textContent =
        `#${data.orderNumber}`;

      els.successTotal.textContent =
        formatMoney(data.total);

      renderOrderItems(data.items);

      state.feedbackRating = 0;
      els.feedbackBox.classList.add('hidden');
      els.feedbackMessage.textContent = '';

      startOrderTracking(
        pending.orderId,
        pending.token,
        data.status
      );

      showState('successState');

      return true;
    } catch (_) {
      clearPendingOrder();
      return false;
    }
  }

  /* =========================================================
     INITIAL LOAD
     ========================================================= */

  async function init() {
    showState('loadingState');

    const tableNumber =
      getTableNumberFromUrl();

    if (!tableNumber) {
      showFatalError(
        'Table not found',
        'Please scan the QR code placed on your table.'
      );
      return;
    }

    startSlowHintTimer();

    try {
      const tableResponse =
        await apiRequest(
          `/public/tables/${tableNumber}`
        );

      state.tableNumber =
        tableResponse.data.tableNumber;

      state.tableName =
        tableResponse.data.tableName;

      const [menuResponse, paymentResponse] = await Promise.all([
        apiRequest('/public/menu'),
        apiRequest('/public/payment-options'),
      ]);

      state.categories =
        menuResponse.categories || [];

      state.items =
        menuResponse.items || [];

      state.paymentOptions = paymentResponse.data || state.paymentOptions;
      const configuredUpiId = String(state.paymentOptions.upiId || '').trim();
      const onlineUpiEnabled = Boolean(state.paymentOptions.onlineUpi || configuredUpiId);
      state.paymentOptions.upiId = configuredUpiId;
      state.paymentOptions.onlineUpi = onlineUpiEnabled;
      if (els.onlinePaymentOption) {
        els.onlinePaymentOption.style.display = onlineUpiEnabled ? 'flex' : 'none';
      }
      if (els.upiHelpText) {
        els.upiHelpText.style.display = onlineUpiEnabled ? 'block' : 'none';
      }
      updatePaymentActions();

      renderApp();

      // Always show the menu first. An old/stale order-status request must
      // never block the customer from seeing the menu.
      showState('app');
      setTimeout(maybeResumePendingUpiPayment, 350);

      const restored = await tryRestorePendingOrder();
      if (restored) return;
    } catch (error) {
      showFatalError(
        'Unable to load menu',
        error.message ||
          'Please try again or ask a staff member for help.'
      );
    }
  }

  /* =========================================================
     MAIN APP
     ========================================================= */

  function renderApp() {
    renderTable();
    renderCategories();
    renderProducts();
    updateCartBar();
  }

  function renderTable() {
    const tableNumber =
      state.tableName
        ? state.tableName.replace(
            /^Table\s*/i,
            ''
          )
        : state.tableNumber;

    els.tableBadge.textContent =
      `Table ${tableNumber}`;
  }

  /* =========================================================
     CATEGORIES
     ========================================================= */

  function renderCategories() {
    els.categoryChips.innerHTML = '';

    els.categoryChips.appendChild(
      createCategoryButton(
        'All',
        'all'
      )
    );

    state.categories.forEach(
      (category) => {
        els.categoryChips.appendChild(
          createCategoryButton(
            category.name,
            category._id
          )
        );
      }
    );
  }

  function createCategoryButton(
    label,
    value
  ) {
    const button =
      document.createElement('button');

    button.type = 'button';

    button.className =
      'chip' +
      (
        state.activeCategory === value
          ? ' active'
          : ''
      );

    button.textContent = label;

    button.addEventListener(
      'click',
      () => {
        state.activeCategory = value;

        renderCategories();
        renderProducts();
      }
    );

    return button;
  }

  /* =========================================================
     SEARCH
     ========================================================= */

  function getFilteredItems() {
    const query =
      state.searchQuery
        .trim()
        .toLowerCase();

    return state.items.filter(
      (item) => {
        const categoryMatch =
          state.activeCategory === 'all' ||
          item.category ===
            state.activeCategory;

        if (!categoryMatch) {
          return false;
        }

        if (!query) {
          return true;
        }

        const name =
          String(item.name || '')
            .toLowerCase();

        const category =
          String(item.categoryName || '')
            .toLowerCase();

        return (
          name.includes(query) ||
          category.includes(query)
        );
      }
    );
  }

  function updateSearchUI() {
    const hasSearch =
      state.searchQuery.trim().length > 0;

    els.clearSearch.classList.toggle(
      'hidden',
      !hasSearch
    );
  }

  /* =========================================================
     PRODUCTS
     ========================================================= */

  function renderProducts() {
    els.productList.innerHTML = '';

    const filteredItems =
      getFilteredItems();

    if (filteredItems.length === 0) {
      els.productList.classList.add(
        'hidden'
      );

      els.searchEmpty.classList.remove(
        'hidden'
      );

      return;
    }

    els.productList.classList.remove(
      'hidden'
    );

    els.searchEmpty.classList.add(
      'hidden'
    );

    const grouped =
      new Map();

    filteredItems.forEach(
      (item) => {
        const categoryName =
          item.categoryName ||
          'Other';

        if (!grouped.has(categoryName)) {
          grouped.set(
            categoryName,
            []
          );
        }

        grouped
          .get(categoryName)
          .push(item);
      }
    );

    grouped.forEach(
      (products, categoryName) => {
        const heading =
          document.createElement('div');

        heading.className =
          'category-heading';

        heading.textContent =
          categoryName;

        els.productList.appendChild(
          heading
        );

        products.forEach(
          (product) => {
            els.productList.appendChild(
              renderProductCard(product)
            );
          }
        );
      }
    );
  }

  function renderProductCard(item) {
    const card =
      document.createElement('div');

    card.className =
      'product-card';

    /* IMAGE */

    if (item.image) {
      const image =
        document.createElement('img');

      image.className =
        'product-image';

      image.loading = 'lazy';

      image.alt =
        item.name || 'Food';

      image.src =
        item.image.startsWith('http')
          ? item.image
          : ASSET_HOST + item.image;

      image.onerror = () => {
        image.style.display = 'none';
      };

      card.appendChild(image);
    } else {
      const placeholder =
        document.createElement('div');

      placeholder.className =
        'product-image placeholder';

      placeholder.textContent =
        String(item.name || 'Food')
          .slice(0, 2)
          .toUpperCase();

      card.appendChild(
        placeholder
      );
    }

    /* INFO */

    const info =
      document.createElement('div');

    info.className =
      'product-info';

    const name =
      document.createElement('div');

    name.className =
      'product-name';

    name.textContent =
      item.name;

    info.appendChild(name);

    if (item.available) {
      const price =
        document.createElement('div');

      price.className =
        'product-price';

      price.textContent =
        formatMoney(item.price);

      info.appendChild(price);
    } else {
      const unavailable =
        document.createElement('div');

      unavailable.className =
        'product-unavailable';

      unavailable.textContent =
        'Currently unavailable';

      info.appendChild(
        unavailable
      );
    }

    card.appendChild(info);

    /* ACTION */

    const action =
      document.createElement('div');

    action.className =
      'product-action';

    action.appendChild(
      renderQuantityControl(item)
    );

    card.appendChild(action);

    return card;
  }

  /* =========================================================
     QUANTITY
     ========================================================= */

  function renderQuantityControl(item) {
    const wrapper =
      document.createElement('div');

    const existing =
      state.cart.get(item._id);

    const quantity =
      existing
        ? existing.quantity
        : 0;

    if (!item.available) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Unavailable';

      button.disabled = true;

      wrapper.appendChild(button);

      return wrapper;
    }

    if (quantity === 0) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Add';

      button.addEventListener(
        'click',
        () => {
          state.cart.set(
            item._id,
            {
              product: item,
              quantity: 1,
            }
          );

          invalidateClientRequestId();
          renderProducts();
          updateCartBar();
        }
      );

      wrapper.appendChild(button);

      return wrapper;
    }

    const stepper =
      document.createElement('div');

    stepper.className =
      'qty-stepper';

    /* MINUS */

    const minus =
      document.createElement('button');

    minus.type = 'button';

    minus.textContent = '−';

    minus.setAttribute(
      'aria-label',
      `Remove one ${item.name}`
    );

    minus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity <= 1) {
          state.cart.delete(
            item._id
          );
        } else {
          line.quantity -= 1;
        }

        invalidateClientRequestId();
        renderProducts();
        updateCartBar();

        if (
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    /* COUNT */

    const count =
      document.createElement('span');

    count.textContent =
      String(quantity);

    /* PLUS */

    const plus =
      document.createElement('button');

    plus.type = 'button';

    plus.textContent = '+';

    plus.setAttribute(
      'aria-label',
      `Add one more ${item.name}`
    );

    plus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity >= 50) {
          return;
        }

        line.quantity += 1;

        invalidateClientRequestId();
        renderProducts();
        updateCartBar();

        if (
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    stepper.appendChild(minus);
    stepper.appendChild(count);
    stepper.appendChild(plus);

    wrapper.appendChild(stepper);

    return wrapper;
  }

  /* =========================================================
     CART
     ========================================================= */

  function getCartSummary() {
    let total = 0;
    let count = 0;

    state.cart.forEach(
      (line) => {
        total +=
          Number(line.product.price || 0) *
          line.quantity;

        count +=
          line.quantity;
      }
    );

    return {
      total,
      count,
    };
  }

  function updateCartBar() {
    const {
      total,
      count,
    } = getCartSummary();

    els.cartBar.classList.toggle(
      'hidden',
      count === 0
    );

    els.cartCount.textContent =
      count === 1
        ? '1 item'
        : `${count} items`;

    els.cartBarTotal.textContent =
      formatMoney(total);
  }

  function renderCart() {
    els.cartLines.innerHTML = '';
    updatePaymentActions();

    const {
      total,
      count,
    } = getCartSummary();

    els.cartItemCount.textContent =
      String(count);

    els.cartTotal.textContent =
      formatMoney(total);

    if (count === 0) {
      const empty =
        document.createElement('div');

      empty.className =
        'cart-empty';

      empty.textContent =
        'Your cart is empty.';

      els.cartLines.appendChild(
        empty
      );

      return;
    }

    state.cart.forEach(
      (line) => {
        const row =
          document.createElement('div');

        row.className =
          'cart-line';

        const left =
          document.createElement('div');

        left.className =
          'cart-line-left';

        const name =
          document.createElement('div');

        name.className =
          'cart-line-name';

        name.textContent =
          line.product.name;

        const price =
          document.createElement('div');

        price.className =
          'cart-line-price';

        price.textContent =
          `${formatMoney(
            line.product.price
          )} × ${line.quantity}`;

        const lineTotal =
          document.createElement('div');

        lineTotal.className =
          'cart-line-total';

        lineTotal.textContent =
          formatMoney(
            line.product.price *
            line.quantity
          );

        left.appendChild(name);
        left.appendChild(price);
        left.appendChild(lineTotal);

        const right =
          document.createElement('div');

        right.appendChild(
          renderQuantityControl(
            line.product
          )
        );

        row.appendChild(left);
        row.appendChild(right);

        els.cartLines.appendChild(
          row
        );
      }
    );
    updatePaymentActions();
  }

  /* =========================================================
     CART OPEN / CLOSE
     ========================================================= */

  function openCart() {
    if (state.cart.size === 0) {
      return;
    }

    renderCart();

    els.checkoutError.classList.add(
      'hidden'
    );

    els.cartOverlay.classList.remove(
      'hidden'
    );

    document.body.style.overflow =
      'hidden';
  }

  function closeCart() {
    els.cartOverlay.classList.add(
      'hidden'
    );

    document.body.style.overflow =
      '';
  }

  /* =========================================================
     PLACE ORDER
     ========================================================= */

  async function placeOrder() {
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before placing the order.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;

    els.checkoutError.classList.add('hidden');
    const selectedPayment = document.querySelector('input[name="paymentMethod"]:checked');
    const paymentMethod = selectedPayment?.value === 'upi' ? 'UPI' : 'CASH';

    // Pay-with-UPI is a separate, dedicated button/flow (see startUpiPayment)
    // because it creates the order immediately and hands off to a UPI app.
    // "Place Order" here only ever handles Pay-at-Counter (CASH).
    if (paymentMethod === 'UPI') {
      await startUpiPayment();
      return;
    }

    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const items = Array.from(state.cart.values()).map((line) => ({
      productId: line.product._id,
      quantity: line.quantity,
    }));

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items,
      paymentMethod: 'CASH',
      clientRequestId: state.clientRequestId,
    };

    els.placeOrderBtn.disabled = true;
    els.placeOrderBtn.textContent = 'Placing order...';
    await submitCreatedOrder(payload);
    els.placeOrderBtn.disabled = false;
    els.placeOrderBtn.textContent = 'Place Order';
  }

  // Builds an Android/iOS-compatible UPI deep link (the `upi://pay` intent
  // scheme every major UPI app — GPay, PhonePe, Paytm, BHIM, etc. —
  // registers itself to handle) and hands off to it via a real user-gesture
  // anchor click. On Android, the OS shows its normal "open with" app
  // chooser for any UPI apps installed on the phone; nothing here needs to
  // enumerate specific apps.
  //
  // Every parameter is percent-encoded and the amount always comes from the
  // ALREADY-CREATED, server-priced order (orderInfo.total) — never a
  // client-computed or user-editable number.
  function buildUpiUrl(orderInfo) {
    const upiId = String(state.paymentOptions.upiId || '').trim();
    const amount = Number(orderInfo.total);
    const params = [
      `pa=${encodeURIComponent(upiId)}`,
      `pn=${encodeURIComponent(state.paymentOptions.cafeName || 'FAST N FRESH CAFE')}`,
      `am=${encodeURIComponent(amount.toFixed(2))}`,
      'cu=INR',
      `tr=${encodeURIComponent(String(orderInfo.orderNumber))}`,
      `tn=${encodeURIComponent(`Order ${orderInfo.orderNumber} - Table ${orderInfo.tableNumber}`)}`,
    ];
    return `upi://pay?${params.join('&')}`;
  }

  // Fires the UPI intent. Returns false (and shows a fallback message)
  // if this browser/page can't attempt an external-app handoff at all —
  // e.g. it isn't in a real user-gesture context — since a failed/blocked
  // intent has no reliable JS callback we can detect.
  function fireUpiIntent(orderInfo) {
    try {
      const upiUrl = buildUpiUrl(orderInfo);
      const upiLink = document.createElement('a');
      upiLink.href = upiUrl;
      upiLink.setAttribute('aria-hidden', 'true');
      upiLink.style.display = 'none';
      document.body.appendChild(upiLink);
      upiLink.click();
      window.setTimeout(() => upiLink.remove(), 1500);

      // If no UPI app is installed, Android/Chrome silently does nothing
      // (no exception is thrown) — there is no JS-visible signal either
      // way. Tell the customer what to check, without claiming success.
      window.setTimeout(() => {
        if (document.visibilityState === 'visible' && els.upiPendingError) {
          els.upiPendingError.textContent =
            "If nothing opened, you may not have a UPI app installed (Google Pay, PhonePe, Paytm, BHIM, etc.). Install one and tap \"Open UPI App Again\", or ask staff to pay by cash.";
          els.upiPendingError.classList.remove('hidden');
        }
      }, 1800);
      return true;
    } catch (_) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent = 'Could not open a UPI app on this device. Please ask staff to pay by cash, or try again.';
        els.upiPendingError.classList.remove('hidden');
      }
      return false;
    }
  }

  function renderUpiPendingScreen(orderInfo) {
    if (els.upiPendingTable) els.upiPendingTable.textContent = orderInfo.tableName || `Table ${orderInfo.tableNumber}`;
    if (els.upiPendingOrderNumber) els.upiPendingOrderNumber.textContent = `#${orderInfo.orderNumber}`;
    if (els.upiPendingTotal) els.upiPendingTotal.textContent = formatMoney(orderInfo.total);
    if (els.upiPendingReferenceInput) els.upiPendingReferenceInput.value = orderInfo.upiReference || '';
    if (els.upiPendingError) els.upiPendingError.classList.add('hidden');

    const submitted = !!orderInfo.referenceSubmitted;
    if (els.upiPendingReferenceInput) els.upiPendingReferenceInput.disabled = submitted;
    if (els.upiSubmitReferenceBtn) els.upiSubmitReferenceBtn.classList.toggle('hidden', submitted);
    if (els.upiPendingStatusCard) els.upiPendingStatusCard.classList.toggle('hidden', !submitted);
    if (els.upiPendingStatusText) {
      els.upiPendingStatusText.textContent = 'Reference received — waiting for staff to confirm your payment.';
    }
    if (els.upiPendingHeading) {
      els.upiPendingHeading.textContent = submitted ? 'Payment submitted' : 'Complete your UPI payment';
    }
  }

  function saveUpiOrderToStorage() {
    if (!state.upiOrder) return;
    try {
      const { pollTimer, ...toStore } = state.upiOrder;
      localStorage.setItem(PENDING_UPI_KEY, JSON.stringify(toStore));
    } catch (_) {}
  }

  function stopUpiPolling() {
    if (state.upiOrder && state.upiOrder.pollTimer) {
      window.clearInterval(state.upiOrder.pollTimer);
      state.upiOrder.pollTimer = null;
    }
  }

  function clearUpiOrder() {
    stopUpiPolling();
    state.upiOrder = null;
    try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
  }

  // While the payment-pending screen is showing, poll the customer-safe
  // order-status endpoint so this page reflects the REAL server-side
  // paymentStatus. This is display-only: it never sets anything to paid
  // itself — that still only happens via authenticated staff checkout.
  function startUpiPolling() {
    stopUpiPolling();
    if (!state.upiOrder) return;
    const poll = async () => {
      if (!state.upiOrder) return;
      try {
        const response = await apiRequest(
          `/public/orders/${encodeURIComponent(state.upiOrder.orderId)}/status?token=${encodeURIComponent(state.upiOrder.token)}`
        );
        const data = response.data || {};
        if (data.status === 'voided' || data.paymentStatus === 'cancelled') {
          clearUpiOrder();
          showState('app');
          return;
        }
        if (data.paymentStatus === 'paid') {
          const orderInfo = state.upiOrder;
          clearUpiOrder();
          if (els.successHeading) els.successHeading.textContent = 'Payment confirmed!';
          if (els.successSubtext) els.successSubtext.textContent = 'Your UPI payment has been verified by the cafe.';
          els.successTable.textContent = data.tableName || orderInfo.tableName;
          els.successOrderNumber.textContent = `#${data.orderNumber || orderInfo.orderNumber}`;
          els.successTotal.textContent = formatMoney(data.total != null ? data.total : orderInfo.total);
          renderOrderItems(data.items || orderInfo.items);
          state.feedbackRating = 0;
          els.feedbackBox.classList.add('hidden');
          els.feedbackMessage.textContent = '';
          startOrderTracking(orderInfo.orderId, orderInfo.token, data.status);
          try { localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({ orderId: orderInfo.orderId, token: orderInfo.token, orderNumber: data.orderNumber || orderInfo.orderNumber })); } catch (_) {}
          showState('successState');
        }
      } catch (_) {
        // Best-effort polling; keep showing the last known state.
      }
    };
    state.upiOrder.pollTimer = window.setInterval(poll, 6000);
  }

  async function startUpiPayment() {
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before paying.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }
    const upiId = String(state.paymentOptions.upiId || '').trim();
    if (!upiId) {
      els.checkoutError.textContent = 'Online UPI payment is not configured right now. Please choose Pay at Counter.';
      els.checkoutError.classList.remove('hidden');
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;

    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items: Array.from(state.cart.values()).map((line) => ({
        productId: line.product._id,
        quantity: line.quantity,
      })),
      paymentMethod: 'UPI',
      clientRequestId: state.clientRequestId,
    };

    if (els.payUpiBtn) {
      els.payUpiBtn.disabled = true;
      els.payUpiBtn.textContent = 'Placing order...';
    }

    // The order is created NOW, at 'payment_initiated' — server-priced,
    // server-verified — BEFORE we ever hand off to a UPI app. This is what
    // gives staff (and this page, on resume) a real, authoritative record
    // of the payment attempt instead of only a client-side draft.
    let response;
    try {
      response = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
    } catch (error) {
      els.checkoutError.textContent = error.message || 'Could not start UPI payment. Please try again.';
      els.checkoutError.classList.remove('hidden');
      if (els.payUpiBtn) {
        els.payUpiBtn.disabled = false;
        els.payUpiBtn.textContent = 'PAY WITH UPI';
      }
      return;
    }

    if (els.payUpiBtn) {
      els.payUpiBtn.disabled = false;
      els.payUpiBtn.textContent = 'PAY WITH UPI';
    }

    const data = response.data;
    state.cart.clear();
    invalidateClientRequestId();
    closeCart();
    updateCartBar();

    state.upiOrder = {
      orderId: data.orderId,
      token: data.trackingToken,
      orderNumber: data.orderNumber,
      tableName: data.tableName,
      tableNumber: data.tableNumber,
      total: data.total,
      items: data.items,
      referenceSubmitted: false,
      pollTimer: null,
    };
    saveUpiOrderToStorage();
    renderUpiPendingScreen(state.upiOrder);
    showState('upiPendingState');
    startUpiPolling();

    // Hand off to the UPI app AFTER the order + pending screen already
    // exist, so a customer who never returns to this tab still has a
    // real, staff-visible order rather than nothing at all.
    fireUpiIntent(state.upiOrder);
  }

  async function submitUpiReference() {
    if (!state.upiOrder) return;
    const upiReference = (els.upiPendingReferenceInput?.value || '').trim();
    if (els.upiPendingError) els.upiPendingError.classList.add('hidden');
    if (!upiReference) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent = 'Please enter the UPI reference / UTR from your payment.';
        els.upiPendingError.classList.remove('hidden');
      }
      return;
    }

    if (els.upiSubmitReferenceBtn) {
      els.upiSubmitReferenceBtn.disabled = true;
      els.upiSubmitReferenceBtn.textContent = 'Submitting...';
    }
    try {
      await apiRequest(`/public/orders/${encodeURIComponent(state.upiOrder.orderId)}/upi-reference`, {
        method: 'POST',
        body: JSON.stringify({ token: state.upiOrder.token, upiReference }),
      });
      state.upiOrder.referenceSubmitted = true;
      state.upiOrder.upiReference = upiReference;
      saveUpiOrderToStorage();
      renderUpiPendingScreen(state.upiOrder);
    } catch (error) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent = error.message || 'Could not submit reference. Please try again.';
        els.upiPendingError.classList.remove('hidden');
      }
    } finally {
      if (els.upiSubmitReferenceBtn) {
        els.upiSubmitReferenceBtn.disabled = false;
        els.upiSubmitReferenceBtn.textContent = "I've Paid — Submit Reference";
      }
    }
  }

  async function cancelUpiOrder() {
    if (!state.upiOrder) return;
    if (!window.confirm('Cancel this order? This cannot be undone.')) return;
    const orderInfo = state.upiOrder;
    if (els.upiCancelBtn) els.upiCancelBtn.disabled = true;
    try {
      await apiRequest(`/public/orders/${encodeURIComponent(orderInfo.orderId)}/cancel`, {
        method: 'POST',
        body: JSON.stringify({ token: orderInfo.token }),
      });
      clearUpiOrder();
      showState('app');
    } catch (error) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent = error.message || 'Could not cancel this order. Please ask staff for help.';
        els.upiPendingError.classList.remove('hidden');
      }
    } finally {
      if (els.upiCancelBtn) els.upiCancelBtn.disabled = false;
    }
  }

  async function submitCreatedOrder(payload) {
    try {
      const response = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      state.cart.clear();
      invalidateClientRequestId();

      closeCart();
      updateCartBar();

      if (els.successHeading) els.successHeading.textContent = 'Order placed!';
      if (els.successSubtext) els.successSubtext.textContent = 'Your order has been sent to the cafe.';
      els.successTable.textContent = response.data.tableName || `Table ${response.data.tableNumber}`;
      els.successOrderNumber.textContent = `#${response.data.orderNumber}`;
      els.successTotal.textContent = formatMoney(response.data.total);
      if (typeof renderOrderItems === 'function') renderOrderItems(response.data.items);

      if (true) {
        state.tracking.orderId = response.data.orderId;
        state.tracking.token = response.data.trackingToken;
        state.feedbackRating = 0;
        els.feedbackBox.classList.add('hidden');
        els.feedbackMessage.textContent = '';
        startOrderTracking(response.data.orderId, response.data.trackingToken, response.data.status);
        try { localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({ orderId: response.data.orderId, token: response.data.trackingToken, orderNumber: response.data.orderNumber })); } catch (_) {}
      }

      showState('successState');
      return true;
    } catch (error) {
      els.checkoutError.textContent = error.message || 'Order failed. Please try again.';
      els.checkoutError.classList.remove('hidden');
      return false;
    }
  }

  // On page load / tab resume, checks whether there's a UPI order this
  // browser started that hasn't been resolved yet (customer left mid-flow,
  // or the page reloaded) and restores the correct screen for it. This
  // reads the order's CURRENT server-side status every time — it never
  // trusts whatever was true when the tab was left.
  let upiResumeBusy = false;

  async function maybeResumePendingUpiPayment() {
    if (upiResumeBusy || state.upiOrder) return;
    let saved = null;
    try {
      const raw = localStorage.getItem(PENDING_UPI_KEY);
      if (raw) saved = JSON.parse(raw);
    } catch (_) {}
    if (!saved || !saved.orderId || !saved.token) return;

    upiResumeBusy = true;
    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(saved.orderId)}/status?token=${encodeURIComponent(saved.token)}`
      );
      const data = response.data || {};

      if (data.status === 'voided' || data.paymentStatus === 'cancelled') {
        try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
        return;
      }

      if (data.paymentStatus === 'paid') {
        try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
        if (els.successHeading) els.successHeading.textContent = 'Payment confirmed!';
        if (els.successSubtext) els.successSubtext.textContent = 'Your UPI payment has been verified by the cafe.';
        els.successTable.textContent = data.tableName || saved.tableName;
        els.successOrderNumber.textContent = `#${data.orderNumber}`;
        els.successTotal.textContent = formatMoney(data.total);
        renderOrderItems(data.items);
        startOrderTracking(saved.orderId, saved.token, data.status);
        try { localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({ orderId: saved.orderId, token: saved.token, orderNumber: data.orderNumber })); } catch (_) {}
        showState('successState');
        return;
      }

      // Still payment_initiated (or, defensively, any other non-final
      // status): show the pending screen with whatever we know so far.
      state.upiOrder = {
        orderId: saved.orderId,
        token: saved.token,
        orderNumber: data.orderNumber || saved.orderNumber,
        tableName: data.tableName || saved.tableName,
        tableNumber: data.tableNumber || saved.tableNumber,
        total: data.total != null ? data.total : saved.total,
        items: data.items || saved.items,
        upiReference: data.paymentMethod === 'UPI' ? saved.upiReference : undefined,
        referenceSubmitted: !!saved.referenceSubmitted,
        pollTimer: null,
      };
      renderUpiPendingScreen(state.upiOrder);
      showState('upiPendingState');
      startUpiPolling();
    } catch (_) {
      // Tracking token/order no longer resolvable (e.g. very old link) —
      // silently drop it and let the customer see a fresh menu instead of
      // getting stuck.
      try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
    } finally {
      upiResumeBusy = false;
    }
  }

  function updatePaymentActions() {
    const selected = document.querySelector('input[name="paymentMethod"]:checked');
    const isUpi = selected?.value === 'upi';
    if (els.payUpiBtn) {
      els.payUpiBtn.classList.toggle('hidden', !isUpi);
      els.payUpiBtn.disabled = state.cart.size === 0;
      els.payUpiBtn.textContent = 'PAY WITH UPI';
    }
    if (els.placeOrderBtn) {
      els.placeOrderBtn.classList.toggle('hidden', isUpi);
      els.placeOrderBtn.textContent = 'Place Order';
    }
  }

  /* =========================================================
     CUSTOMER ORDER TRACKING
     ========================================================= */

  function stopOrderTracking() {
    if (state.tracking.timer) {
      window.clearInterval(state.tracking.timer);
      state.tracking.timer = null;
    }
  }

  function orderStatusLabel(status) {
    switch (status) {
      case 'preparing': return 'Preparing your order';
      case 'ready': return 'Your order is ready';
      case 'completed': return 'Order completed';
      case 'voided': return 'Order cancelled';
      default: return 'Order received';
    }
  }

  function renderOrderStatus(status) {
    if (!els.successStatus || !els.successStatusText) return;
    const safe = status || 'open';
    els.successStatus.className = `order-status-card status-${safe}`;
    els.successStatusText.textContent = orderStatusLabel(safe);
  }

  async function refreshOrderStatus() {
    if (!state.tracking.orderId || !state.tracking.token) return;
    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(state.tracking.orderId)}/status?token=${encodeURIComponent(state.tracking.token)}`
      );
      const data = response.data || {};
      state.tracking.status = data.status || 'open';
      renderOrderStatus(state.tracking.status);

      if (state.tracking.status === 'completed' || state.tracking.status === 'voided') {
        stopOrderTracking();
        if (state.tracking.status === 'completed' && els.feedbackBox) els.feedbackBox.classList.remove('hidden');
      }
    } catch (_) {
      // Tracking is best-effort; keep the last known status visible.
    }
  }

  function startOrderTracking(orderId, token, status) {
    stopOrderTracking();
    state.tracking.orderId = orderId || null;
    state.tracking.token = token || null;
    state.tracking.status = status || 'open';
    renderOrderStatus(state.tracking.status);
    if (!state.tracking.orderId || !state.tracking.token) return;
    state.tracking.timer = window.setInterval(refreshOrderStatus, 8000);
  }

  /* =========================================================
     EVENTS
     ========================================================= */

  els.cartBar.addEventListener(
    'click',
    openCart
  );

  els.closeCart.addEventListener(
    'click',
    closeCart
  );

  els.cartOverlay.addEventListener(
    'click',
    (event) => {
      if (
        event.target ===
        els.cartOverlay
      ) {
        closeCart();
      }
    }
  );

  els.placeOrderBtn.addEventListener(
    'click',
    placeOrder
  );

  if (els.payUpiBtn) {
    els.payUpiBtn.addEventListener('click', startUpiPayment);
  }

  if (els.upiReopenBtn) {
    els.upiReopenBtn.addEventListener('click', () => {
      if (state.upiOrder) fireUpiIntent(state.upiOrder);
    });
  }

  if (els.upiSubmitReferenceBtn) {
    els.upiSubmitReferenceBtn.addEventListener('click', submitUpiReference);
  }

  if (els.upiCancelBtn) {
    els.upiCancelBtn.addEventListener('click', cancelUpiOrder);
  }

  document.querySelectorAll('input[name="paymentMethod"]').forEach((input) => {
    input.addEventListener('change', () => {
      updatePaymentActions();
    });
  });

  if (els.feedbackStars) {
    els.feedbackStars.querySelectorAll('button').forEach((button) => {
      button.addEventListener('click', () => {
        state.feedbackRating = Number(button.dataset.rating || 0);
        els.feedbackStars.querySelectorAll('button').forEach((b) => b.classList.toggle('selected', Number(b.dataset.rating || 0) <= state.feedbackRating));
      });
    });
  }

  if (els.submitFeedbackBtn) {
    els.submitFeedbackBtn.addEventListener('click', async () => {
      if (!state.tracking.orderId || !state.tracking.token || !state.feedbackRating) {
        els.feedbackMessage.textContent = 'Please select a rating first.';
        return;
      }
      els.submitFeedbackBtn.disabled = true;
      try {
        await apiRequest('/feedback', { method: 'POST', body: JSON.stringify({ orderId: state.tracking.orderId, token: state.tracking.token, rating: state.feedbackRating, comment: els.feedbackComment.value.trim(), customerName: els.customerName?.value?.trim() || '' }) });
        els.feedbackMessage.textContent = 'Thanks! Your feedback was received.';
        els.submitFeedbackBtn.textContent = 'Feedback Sent';
      } catch (error) { els.feedbackMessage.textContent = error.message || 'Could not send feedback.'; }
      finally { els.submitFeedbackBtn.disabled = false; }
    });
  }

  /* SEARCH */

  els.searchInput.addEventListener(
    'input',
    () => {
      state.searchQuery =
        els.searchInput.value;

      updateSearchUI();
      renderProducts();
    }
  );

  function clearSearch() {
    els.searchInput.value = '';

    state.searchQuery = '';

    updateSearchUI();
    renderProducts();

    els.searchInput.focus();
  }

  els.clearSearch.addEventListener(
    'click',
    clearSearch
  );

  els.clearSearchBtn.addEventListener(
    'click',
    clearSearch
  );

  /* RETRY */

  els.retryBtn.addEventListener(
    'click',
    () => {
      init();
    }
  );

  /* DONE */

  els.doneBtn.addEventListener(
    'click',
    () => {
      stopOrderTracking();
      state.tracking.orderId = null;
      state.tracking.token = null;
      clearPendingOrder();
      window.location.reload();
    }
  );

  /* ESC */

  document.addEventListener(
    'keydown',
    (event) => {
      if (
        event.key === 'Escape' &&
        !els.cartOverlay.classList.contains(
          'hidden'
        )
      ) {
        closeCart();
      }
    }
  );

  window.addEventListener('pageshow', () => {
    setTimeout(maybeResumePendingUpiPayment, 350);
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setTimeout(maybeResumePendingUpiPayment, 350);
    }
  });

  /* START */

  init();
})();