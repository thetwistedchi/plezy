//! C interface to Brave's adblock-rust engine, for the in-app browser
//! (windows/runner/browser). Strings are UTF-8 and NUL-terminated; strings
//! returned by this library are freed with `plezy_adblock_free_string`.

use std::collections::HashSet;
use std::ffi::{c_char, c_int, CStr, CString};
use std::fs;
use std::panic::{catch_unwind, AssertUnwindSafe};

use adblock::lists::{FilterSet, ParseOptions};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use adblock::Engine;
use serde::Deserialize;

/// What the engine was built from. `cacheKey` changes whenever a list or the
/// user's own filters change; an unchanged key loads the saved engine instead
/// of parsing every list again.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Config {
    #[serde(default)]
    lists: Vec<ListConfig>,
    #[serde(default)]
    user_filters: String,
    #[serde(default)]
    resources: Option<String>,
    #[serde(default)]
    cache: Option<String>,
    #[serde(default)]
    cache_key: String,
}

#[derive(Deserialize)]
struct ListConfig {
    path: String,
    /// Lists from uBlock Origin's own maintainers may use trusted scriptlets.
    #[serde(default)]
    trusted: bool,
}

pub struct PlezyAdblock {
    engine: Engine,
}

const TRUSTED: PermissionMask = PermissionMask::from_bits(0xff);

fn read_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }.to_str().ok()
}

fn to_c(text: String) -> *mut c_char {
    CString::new(text.replace('\0', "")).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

fn load_resources(path: &Option<String>) -> Vec<Resource> {
    path.as_ref()
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|text| serde_json::from_str::<Vec<Resource>>(&text).ok())
        .unwrap_or_default()
}

fn build(config: &Config) -> Engine {
    let key_path = config.cache.as_ref().map(|c| format!("{c}.key"));
    if let (Some(cache), Some(key_path)) = (&config.cache, &key_path) {
        let same_key = !config.cache_key.is_empty()
            && fs::read_to_string(key_path).map(|k| k == config.cache_key).unwrap_or(false);
        if same_key {
            if let Ok(bytes) = fs::read(cache) {
                let mut engine = Engine::default();
                if engine.deserialize(&bytes).is_ok() {
                    engine.use_resources(load_resources(&config.resources));
                    return engine;
                }
            }
        }
    }

    let mut set = FilterSet::new(false);
    for list in &config.lists {
        let Ok(bytes) = fs::read(&list.path) else { continue };
        let text = String::from_utf8_lossy(&bytes);
        let options = ParseOptions {
            permissions: if list.trusted { TRUSTED } else { PermissionMask::default() },
            ..ParseOptions::default()
        };
        set.add_filter_list(text.into_owned(), options);
    }
    if !config.user_filters.trim().is_empty() {
        set.add_filter_list(config.user_filters.clone(), ParseOptions { permissions: TRUSTED, ..ParseOptions::default() });
    }
    let mut engine = Engine::new_with_filter_set(set);
    if let (Some(cache), Some(key_path)) = (&config.cache, &key_path) {
        if !config.cache_key.is_empty() && fs::write(cache, engine.serialize()).is_ok() {
            let _ = fs::write(key_path, &config.cache_key);
        }
    }
    engine.use_resources(load_resources(&config.resources));
    engine
}

/// Builds an engine as described by `config_json`. Returns null on bad input.
/// Can take a second or two for large lists: call it off the UI thread.
#[no_mangle]
pub extern "C" fn plezy_adblock_load(config_json: *const c_char) -> *mut PlezyAdblock {
    let Some(json) = read_str(config_json) else { return std::ptr::null_mut() };
    let Ok(config) = serde_json::from_str::<Config>(json) else { return std::ptr::null_mut() };
    catch_unwind(AssertUnwindSafe(|| Box::into_raw(Box::new(PlezyAdblock { engine: build(&config) }))))
        .unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn plezy_adblock_free(engine: *mut PlezyAdblock) {
    if !engine.is_null() {
        drop(unsafe { Box::from_raw(engine) });
    }
}

#[no_mangle]
pub extern "C" fn plezy_adblock_free_string(text: *mut c_char) {
    if !text.is_null() {
        drop(unsafe { CString::from_raw(text) });
    }
}

/// 0 = allow, 1 = block, 2 = replace with `*redirect` (a data: URL, freed by
/// the caller with `plezy_adblock_free_string`).
#[no_mangle]
pub extern "C" fn plezy_adblock_check(
    engine: *const PlezyAdblock,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
    redirect: *mut *mut c_char,
) -> c_int {
    if !redirect.is_null() {
        unsafe { *redirect = std::ptr::null_mut() };
    }
    let (Some(engine), Some(url), Some(source), Some(kind)) =
        (unsafe { engine.as_ref() }, read_str(url), read_str(source_url), read_str(request_type))
    else {
        return 0;
    };
    let Ok(request) = Request::new(url, source, kind, "get") else { return 0 };
    let result = engine.engine.check_network_request(&request);
    if !result.should_block() {
        return 0;
    }
    if let Some(target) = result.redirect {
        if !redirect.is_null() {
            unsafe { *redirect = to_c(target) };
        }
        return 2;
    }
    1
}

/// Cosmetic filtering for a page, as JSON:
/// `{"hide":[selectors],"exceptions":[...],"script":"...","generichide":bool}`.
#[no_mangle]
pub extern "C" fn plezy_adblock_url_cosmetic(engine: *const PlezyAdblock, url: *const c_char) -> *mut c_char {
    let (Some(engine), Some(url)) = (unsafe { engine.as_ref() }, read_str(url)) else {
        return std::ptr::null_mut();
    };
    let r = engine.engine.url_cosmetic_resources(url);
    let json = serde_json::json!({
        "hide": r.hide_selectors,
        "exceptions": r.exceptions,
        "script": r.injected_script,
        "generichide": r.generichide,
    });
    to_c(json.to_string())
}

#[derive(Deserialize)]
struct ClassIdQuery {
    #[serde(default)]
    c: Vec<String>,
    #[serde(default)]
    i: Vec<String>,
    #[serde(default)]
    e: Vec<String>,
}

/// Generic hiding rules for classes and ids seen on a page. Input JSON
/// `{"c":[classes],"i":[ids],"e":[exceptions]}`, output a JSON array of
/// selectors.
#[no_mangle]
pub extern "C" fn plezy_adblock_hidden_selectors(engine: *const PlezyAdblock, query_json: *const c_char) -> *mut c_char {
    let (Some(engine), Some(json)) = (unsafe { engine.as_ref() }, read_str(query_json)) else {
        return std::ptr::null_mut();
    };
    let Ok(query) = serde_json::from_str::<ClassIdQuery>(json) else { return std::ptr::null_mut() };
    let exceptions: HashSet<String> = query.e.into_iter().collect();
    let selectors = engine.engine.hidden_class_id_selectors(&query.c, &query.i, &exceptions);
    to_c(serde_json::to_string(&selectors).unwrap_or_else(|_| "[]".into()))
}

fn hide_css<'a>(selectors: impl IntoIterator<Item = &'a String>) -> String {
    // One rule per selector: an invalid selector only drops its own rule.
    let mut css = String::new();
    for selector in selectors {
        css.push_str(selector);
        css.push_str("{display:none!important}\n");
    }
    css
}

const ADD_STYLE: &str = "const a=c=>{const s=document.createElement('style');s.textContent=c;\
const put=()=>{const r=document.head||document.documentElement;if(!r)return false;r.appendChild(s);return true;};\
if(!put()){const o=new MutationObserver(()=>{if(put())o.disconnect();});o.observe(document,{childList:true,subtree:true});}};";

/// The script to run at the start of every document of the page at `url`:
/// site-specific hiding rules and scriptlets. Null when there is nothing to
/// run. `*exceptions_json` receives the page's generic hiding exceptions (for
/// `plezy_adblock_generic_script`), `*generichide` whether generic hiding is
/// off for the page.
#[no_mangle]
pub extern "C" fn plezy_adblock_page_script(
    engine: *const PlezyAdblock,
    url: *const c_char,
    exceptions_json: *mut *mut c_char,
    generichide: *mut c_int,
) -> *mut c_char {
    if !exceptions_json.is_null() {
        unsafe { *exceptions_json = std::ptr::null_mut() };
    }
    if !generichide.is_null() {
        unsafe { *generichide = 0 };
    }
    let (Some(engine), Some(url)) = (unsafe { engine.as_ref() }, read_str(url)) else {
        return std::ptr::null_mut();
    };
    let Ok(request) = Request::new(url, url, "document", "get") else { return std::ptr::null_mut() };
    let host = request.hostname.clone();
    let r = engine.engine.url_cosmetic_resources(url);
    if !exceptions_json.is_null() {
        let list: Vec<&String> = r.exceptions.iter().collect();
        unsafe { *exceptions_json = to_c(serde_json::to_string(&list).unwrap_or_else(|_| "[]".into())) };
    }
    if !generichide.is_null() {
        unsafe { *generichide = r.generichide as c_int };
    }
    if r.hide_selectors.is_empty() && r.injected_script.trim().is_empty() {
        return std::ptr::null_mut();
    }
    let mut js = String::from("(()=>{");
    // Only in documents of this site (the page and its same-site frames).
    js.push_str(&format!("if(location.hostname!=={})return;", serde_json::to_string(&host).unwrap_or_default()));
    if !r.hide_selectors.is_empty() {
        js.push_str(ADD_STYLE);
        js.push_str(&format!("a({});", serde_json::to_string(&hide_css(&r.hide_selectors)).unwrap_or_default()));
    }
    if !r.injected_script.trim().is_empty() {
        js.push_str("try{\n");
        js.push_str(&r.injected_script);
        js.push_str("\n}catch(e){}");
    }
    js.push_str("})();");
    to_c(js)
}

#[derive(Deserialize)]
struct ClassIds {
    #[serde(default)]
    c: Vec<String>,
    #[serde(default)]
    i: Vec<String>,
}

/// A script adding generic hiding rules for the classes and ids a page
/// reported (`{"c":[..],"i":[..]}`), or null when none apply.
#[no_mangle]
pub extern "C" fn plezy_adblock_generic_script(
    engine: *const PlezyAdblock,
    class_ids_json: *const c_char,
    exceptions_json: *const c_char,
) -> *mut c_char {
    let (Some(engine), Some(json)) = (unsafe { engine.as_ref() }, read_str(class_ids_json)) else {
        return std::ptr::null_mut();
    };
    let Ok(query) = serde_json::from_str::<ClassIds>(json) else { return std::ptr::null_mut() };
    let exceptions: HashSet<String> = read_str(exceptions_json)
        .and_then(|e| serde_json::from_str::<Vec<String>>(e).ok())
        .unwrap_or_default()
        .into_iter()
        .collect();
    let selectors = engine.engine.hidden_class_id_selectors(&query.c, &query.i, &exceptions);
    if selectors.is_empty() {
        return std::ptr::null_mut();
    }
    let css = hide_css(&selectors);
    to_c(format!(
        "(()=>{{{ADD_STYLE}a({});}})();",
        serde_json::to_string(&css).unwrap_or_default()
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_send_sync<T: Send + Sync>() {}

    #[test]
    fn engine_is_send_sync() {
        assert_send_sync::<PlezyAdblock>();
    }
}
