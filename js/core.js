// Shared helpers for every Upstride page: Supabase client, formatting, header state.
(function () {
  const cfg = window.UPSTRIDE_CONFIG || {};
  const hasValues = cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY &&
    !cfg.SUPABASE_URL.startsWith('YOUR_') && !cfg.SUPABASE_ANON_KEY.startsWith('YOUR_');
  // Supabase's newer "sb_publishable_…" keys must travel only in the apikey header.
  // The client also copies the key into "Authorization: Bearer" when nobody is signed in,
  // which the platform rejects, so drop that copy (a signed-in user's token is kept).
  const key = cfg.SUPABASE_ANON_KEY || '';
  const fetchForPublishableKey = (input, init = {}) => {
    const headers = new Headers(init.headers || (input instanceof Request ? input.headers : undefined));
    if (headers.get('Authorization') === 'Bearer ' + key) headers.delete('Authorization');
    return fetch(input, { ...init, headers });
  };
  const sb = hasValues && window.supabase
    ? window.supabase.createClient(cfg.SUPABASE_URL, key, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'implicit' },
        global: key.startsWith('sb_publishable_') ? { fetch: fetchForPublishableKey } : {}
      })
    : null;

  const NR = {
    sb,
    ready: !!sb,
    FIELDS: ['Software Development', 'Business Analysis', 'Quality Assurance', 'Data Analytics', 'Marketing', 'Leadership'],
    STAGES: ['Final-year student', 'Recent graduate', '1–3 years experience', '3–8 years experience', '8+ years experience'],
    EXPERIENCE: ['3–5 years', '5–10 years', '10–15 years', '15+ years'],
    AVAILABILITY: ['Weekday evenings', 'Weekends', 'Both'],
    PLATFORM_FEE: 0.15,
    FEE_COLLECTED: !!cfg.FEE_COLLECTED,
    CONTACT_EMAIL: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cfg.CONTACT_EMAIL || '') ? cfg.CONTACT_EMAIL : '',

    esc(s) {
      return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    },
    inr(n) { return '₹' + Number(n || 0).toLocaleString('en-IN'); },
    when(ts) {
      return new Intl.DateTimeFormat('en-IN', {
        weekday: 'short', day: 'numeric', month: 'short', year: 'numeric',
        hour: 'numeric', minute: '2-digit', timeZone: 'Asia/Kolkata'
      }).format(new Date(ts)) + ' IST';
    },
    initials(name) {
      const p = String(name || '?').trim().split(/\s+/);
      return ((p[0] || '?')[0] + (p.length > 1 ? p[p.length - 1][0] : '')).toUpperCase();
    },
    one(x) { return Array.isArray(x) ? x[0] : x; },
    options(list, selected) {
      return list.map(v => `<option${v === selected ? ' selected' : ''}>${NR.esc(v)}</option>`).join('');
    },
    // Round profile photo, or initials when there's no photo.
    avatar(name, url, size) {
      const px = size || 44;
      const safe = /^https:\/\/[^/]+\/storage\/v1\/object\/public\/avatars\//.test(url || '') ? url : '';
      return `<span class="av" style="width:${px}px;height:${px}px;font-size:${Math.round(px * 0.34)}px" aria-hidden="true">${
        NR.esc(NR.initials(name))}${safe ? `<img src="${NR.esc(safe)}" alt="" loading="lazy" onerror="this.remove()">` : ''}</span>`;
    },

    // Crop to a square, shrink to 400px and upload as the user's profile photo. Returns the new URL.
    async uploadAvatar(file, uid) {
      if (!file || !/^image\/(jpeg|png|webp|heic|heif)$/i.test(file.type || 'image/jpeg')) throw new Error('Choose a JPG, PNG or WebP photo.');
      if (file.size > 15 * 1024 * 1024) throw new Error('That photo is too large. Choose one under 15 MB.');
      const img = await new Promise((ok, bad) => {
        const i = new Image(); const u = URL.createObjectURL(file);
        i.onload = () => { URL.revokeObjectURL(u); ok(i); };
        i.onerror = () => { URL.revokeObjectURL(u); bad(new Error('That file could not be read as a photo.')); };
        i.src = u;
      });
      const side = Math.min(img.naturalWidth, img.naturalHeight), out = 400;
      const c = document.createElement('canvas'); c.width = out; c.height = out;
      c.getContext('2d').drawImage(img, (img.naturalWidth - side) / 2, (img.naturalHeight - side) / 2, side, side, 0, 0, out, out);
      const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.86));
      const path = `${uid}/avatar.jpg`;
      const up = await sb.storage.from('avatars').upload(path, blob, { upsert: true, contentType: 'image/jpeg', cacheControl: '3600' });
      if (up.error) throw up.error;
      const url = sb.storage.from('avatars').getPublicUrl(path).data.publicUrl + '?v=' + Date.now();
      const { error } = await sb.from('profiles').update({ avatar_url: url }).eq('id', uid);
      if (error) throw error;
      return url;
    },

    // Free video room (Jitsi Meet, no account needed), used when a guide doesn't add their own link.
    newMeetLink() {
      const abc = 'abcdefghjkmnpqrstuvwxyz23456789', bytes = new Uint8Array(12);
      crypto.getRandomValues(bytes);
      return 'https://meet.jit.si/Upstride-' + Array.from(bytes, x => abc[x % abc.length]).join('');
    },

    safeUrl(u) {
      return /^https:\/\//i.test(u || '') ? u : '';
    },
    // A profile link as typed by a person: add https:// when it is missing, so "linkedin.com/in/name" still opens.
    webUrl(u) {
      u = String(u || '').trim().replace(/\s+/g, '');
      if (!u) return '';
      if (/^http:\/\//i.test(u)) u = 'https://' + u.slice(7);
      else if (!/^https:\/\//i.test(u)) { if (/^[a-z][a-z0-9+.-]*:/i.test(u)) return ''; u = 'https://' + u.replace(/^\/+/, ''); }
      try { const p = new URL(u); return p.hostname.includes('.') ? p.href : ''; } catch (e) { return ''; }
    },

    // Dates and times are always shown in India time.
    istDate(ts) { return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(ts)); },
    istTime(ts) { return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', hour: 'numeric', minute: '2-digit' }).format(new Date(ts)); },
    istDay(ts) { return new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', weekday: 'short', day: 'numeric', month: 'short' }).format(new Date(ts)); },
    todayIST() { return NR.istDate(Date.now()); },

    // Pick a date, then one of that day's free times. Returns { value(), slot() }.
    slotPicker(el, slots, emptyText) {
      const byDay = {};
      (slots || []).forEach(s => { (byDay[NR.istDate(s.starts_at)] = byDay[NR.istDate(s.starts_at)] || []).push(s); });
      const days = Object.keys(byDay).sort();
      let day = days[0], chosen = null;
      if (!days.length) {
        el.innerHTML = `<div class="empty">${NR.esc(emptyText || 'No open time slots right now.')}</div>`;
        return { value: () => null, slot: () => null };
      }
      const render = () => {
        el.innerHTML = `
          <div class="chip-label">Date</div>
          <div class="chip-row" role="group" aria-label="Date">${days.map(d => `
            <button type="button" class="chip day${d === day ? ' on' : ''}" data-day="${d}" aria-pressed="${d === day}">
              <b>${NR.esc(NR.istDay(byDay[d][0].starts_at))}</b><small>${byDay[d].length} slot${byDay[d].length === 1 ? '' : 's'}</small></button>`).join('')}</div>
          <div class="chip-label">Time (IST)</div>
          <div class="chip-row flowing" role="group" aria-label="Time">${byDay[day].map(s => `
            <button type="button" class="chip${s.id === chosen ? ' on' : ''}" data-slot="${s.id}" aria-pressed="${s.id === chosen}">${NR.esc(NR.istTime(s.starts_at))}</button>`).join('')}</div>`;
      };
      el.onclick = e => {
        const d = e.target.closest('[data-day]');
        if (d) { day = d.dataset.day; render(); return; }
        const t = e.target.closest('[data-slot]');
        if (t) { chosen = t.dataset.slot; render(); }
      };
      render();
      return { value: () => chosen, slot: () => (slots || []).find(s => s.id === chosen) || null };
    },

    toast(msg, bad) {
      document.querySelectorAll('.toast').forEach(t => t.remove());
      const t = document.createElement('div');
      t.className = 'toast' + (bad ? ' bad' : '');
      t.setAttribute('role', 'status');
      t.textContent = msg;
      // inside an open pop-up, show the message there so it isn't hidden behind it
      (document.querySelector('dialog[open]') || document.body).appendChild(t);
      setTimeout(() => t.remove(), bad ? 6000 : 3500);
    },

    // Turn database and auth errors into sentences people can act on.
    explain(err) {
      const m = (err && (err.message || err.error_description || String(err))) || 'Something went wrong.';
      if (/avatar_url|payout_upi|Bucket not found|bucket/i.test(m)) return 'The database needs an update first: run supabase/migrations/004_profile_photos.sql in the Supabase SQL Editor.';
      if (/is_rejected/.test(m)) return 'The database needs an update first: run supabase/migrations/002_guide_rejection.sql in the Supabase SQL Editor.';
      if (/open_slots|availability_slots|reschedule_booking|slot_id|could not find the function/i.test(m)) return 'The database needs an update first: run supabase/migrations/003_slots_and_reschedule.sql in the Supabase SQL Editor.';
      if (/bookings_one_per_slot/.test(m)) return 'That time slot has just been taken. Please choose another.';
      if (/duplicate key.*availability_slots|availability_slots_guide_id_starts_at_key/.test(m)) return 'You already have a slot at that time.';
      if (/bookings_no_double_accept/.test(m)) return 'You already have a session accepted at that time. Decline this one or cancel the other first.';
      if (/Invalid login credentials/i.test(m)) return 'Email or password is incorrect.';
      if (/Email not confirmed/i.test(m)) return 'Please confirm your email first. Check your inbox for the link from Upstride.';
      if (/already registered|already been registered/i.test(m)) return 'An account with this email already exists. Sign in instead.';
      if (/Password should be at least/i.test(m)) return 'Use a password with at least 8 characters.';
      if (/email rate limit/i.test(m)) return 'We have sent too many confirmation emails in the last hour. Please try again later.';
      if (/rate limit|too many/i.test(m)) return 'Too many attempts. Wait a few minutes and try again.';
      if (/meeting_link/.test(m)) return 'The meeting link must start with https://';
      if (/Failed to fetch|NetworkError/i.test(m)) return 'Could not reach the server. Check your connection and try again.';
      return m.replace(/^ERROR:\s*/, '');
    },

    async user() {
      if (!sb) return null;
      const { data } = await sb.auth.getSession();
      return data.session ? data.session.user : null;
    },

    async profile(uid) {
      const { data, error } = await sb.from('profiles').select('*').eq('id', uid).single();
      if (error) throw error;
      return data;
    },

    // Send people to the login page and bring them back afterwards.
    loginUrl(extra) {
      const next = encodeURIComponent(location.pathname.split('/').pop() + location.search);
      return `login.html?next=${next}${extra ? '&' + extra : ''}`;
    },

    notReadyHtml() {
      return `<div class="notice">The database isn't connected yet. Add your Supabase URL and anon key to <code>js/config.js</code> (see the README).</div>`;
    },

    // Phone menu: the section links hide below 900px, so a menu button opens them as a panel.
    menu() {
      const head = document.querySelector('header.top');
      const nav = head && head.querySelector('nav.links');
      if (!nav || head.querySelector('.menu-btn')) return;
      nav.id = nav.id || 'site-nav';
      const btn = document.createElement('button');
      btn.type = 'button'; btn.className = 'menu-btn';
      btn.setAttribute('aria-label', 'Menu'); btn.setAttribute('aria-expanded', 'false'); btn.setAttribute('aria-controls', nav.id);
      btn.innerHTML = '<span></span><span></span><span></span>';
      head.querySelector('.wrap').appendChild(btn);
      const set = open => { head.classList.toggle('menu-open', open); btn.setAttribute('aria-expanded', String(open)); };
      btn.addEventListener('click', () => set(!head.classList.contains('menu-open')));
      nav.addEventListener('click', e => { if (e.target.closest('a')) set(false); });
      document.addEventListener('keydown', e => { if (e.key === 'Escape') set(false); });
    },

    // Contact line in the footer and on the legal pages, from js/config.js.
    contact() {
      document.querySelectorAll('[data-contact]').forEach(el => {
        const optional = el.hasAttribute('data-contact-optional');
        if (NR.CONTACT_EMAIL) {
          el.innerHTML = `${optional ? ' · Contact: ' : ''}<a href="mailto:${NR.esc(NR.CONTACT_EMAIL)}">${NR.esc(NR.CONTACT_EMAIL)}</a>`;
          el.hidden = false;
        } else if (!optional) {
          el.textContent = 'our support email (to be announced on this page)';
        }
      });
    },

    // Header buttons change when someone is signed in.
    async header() {
      const slot = document.querySelector('[data-auth-slot]');
      if (!slot) return;
      const u = await NR.user();
      if (u) {
        try { const pr = await NR.profile(u.id); document.documentElement.dataset.role = pr.role; NR.role = pr.role; } catch (e) {}
        const nav = document.querySelector('header.top nav.links');
        if (nav && !nav.querySelector('a[href="dashboard.html"]')) nav.insertAdjacentHTML('beforeend', '<a href="dashboard.html">Dashboard</a>');
        const onDash = /dashboard\.html$/.test(location.pathname);
        slot.innerHTML = `${onDash ? '' : '<a class="btn ghost sm dash-btn" href="dashboard.html">Dashboard</a>'}
          <button class="btn sm" type="button" data-signout>Sign out</button>`;
        slot.querySelector('[data-signout]').addEventListener('click', async () => {
          await sb.auth.signOut();
          location.href = 'index.html';
        });
      } else {
        slot.innerHTML = `<a class="btn ghost sm" href="login.html">Sign in</a>
          <a class="btn sm" href="login.html?mode=signup">Join</a>`;
      }
    }
  };

  window.NR = NR;
  document.addEventListener('DOMContentLoaded', () => { NR.menu(); NR.contact(); NR.header().catch(() => {}); });
})();
