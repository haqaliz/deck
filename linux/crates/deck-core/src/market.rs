use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::providers::{self, FetchError};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum MarketCurrency {
    #[default]
    Usd,
    Eur,
    Cad,
    Aed,
    Irr,
    Irt,
}

impl MarketCurrency {
    pub fn label(self) -> &'static str {
        match self {
            Self::Usd => "USD",
            Self::Eur => "EUR",
            Self::Cad => "CAD",
            Self::Aed => "AED",
            Self::Irr => "IRR",
            Self::Irt => "IRT",
        }
    }

    pub fn from_label(label: &str) -> Option<Self> {
        match label.trim().to_uppercase().as_str() {
            "USD" => Some(Self::Usd),
            "EUR" => Some(Self::Eur),
            "CAD" => Some(Self::Cad),
            "AED" => Some(Self::Aed),
            "IRR" => Some(Self::Irr),
            "IRT" => Some(Self::Irt),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MarketKind {
    Crypto,
    Fiat,
    Gold,
    Stock,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoinSearchHit {
    pub symbol: String,
    pub name: String,
    pub rank: Option<u64>,
}

/// CoinGecko's `/search` endpoint: compact, market-cap ordered and carries the
/// rank that makes a symbol choice possible.
pub fn search_coins(query: &str) -> Result<Vec<CoinSearchHit>, FetchError> {
    let query = query.trim();
    if query.chars().count() < 2 {
        return Ok(Vec::new());
    }
    let body = providers::get(
        &format!(
            "https://api.coingecko.com/api/v3/search?query={}",
            encode_query(query)
        ),
        &[],
    )?;
    parse_coin_search(&body).ok_or(FetchError::InvalidPayload)
}

/// Yahoo Finance's symbol search, merged with the coin hits by the picker.
pub fn search_stocks(query: &str) -> Result<Vec<CoinSearchHit>, FetchError> {
    let query = query.trim();
    if query.chars().count() < 2 {
        return Ok(Vec::new());
    }
    let body = providers::get(
        &format!(
            "https://query1.finance.yahoo.com/v1/finance/search?q={}&quotesCount=8&newsCount=0",
            encode_query(query)
        ),
        &[("Accept", "application/json")],
    )?;
    parse_stock_search(&body).ok_or(FetchError::InvalidPayload)
}

fn parse_stock_search(body: &str) -> Option<Vec<CoinSearchHit>> {
    let json: Value = serde_json::from_str(body).ok()?;
    Some(
        json.get("quotes")?
            .as_array()?
            .iter()
            .filter_map(|quote| {
                let symbol = quote.get("symbol")?.as_str()?.to_uppercase();
                if symbol.is_empty() {
                    return None;
                }
                Some(CoinSearchHit {
                    symbol,
                    name: quote
                        .get("shortname")
                        .or_else(|| quote.get("longname"))
                        .and_then(Value::as_str)
                        .unwrap_or("")
                        .to_owned(),
                    rank: None,
                })
            })
            .take(8)
            .collect(),
    )
}

fn parse_coin_search(body: &str) -> Option<Vec<CoinSearchHit>> {
    let json: Value = serde_json::from_str(body).ok()?;
    Some(
        json.get("coins")?
            .as_array()?
            .iter()
            .filter_map(|coin| {
                Some(CoinSearchHit {
                    symbol: coin.get("symbol")?.as_str()?.to_uppercase(),
                    name: coin.get("name")?.as_str()?.to_owned(),
                    rank: coin.get("market_cap_rank").and_then(Value::as_u64),
                })
            })
            .take(8)
            .collect(),
    )
}

fn encode_query(value: &str) -> String {
    let mut out = String::new();
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MarketRow {
    pub symbol: String,
    pub name: String,
    pub kind: MarketKind,
    pub price: f64,
    pub day_change_pct: Option<f64>,
    pub sparkline: Option<Vec<f64>>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MarketSnapshot {
    pub display_currency: MarketCurrency,
    pub rows: Vec<MarketRow>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CryptoQuote {
    pub symbol: String,
    pub name: String,
    pub price_usd: Option<f64>,
    pub change_24h: Option<f64>,
    pub sparkline: Option<Vec<f64>>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct WallexQuote {
    pub toman_per_usdt: Option<f64>,
    pub change_24h: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StockQuote {
    pub name: String,
    pub price_usd: Option<f64>,
    pub change_pct: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum YahooResult {
    Quote(StockQuote),
    NoData,
    Malformed,
}

pub fn parse_coingecko(body: &str) -> Option<Vec<CryptoQuote>> {
    let list = serde_json::from_str::<Vec<Value>>(body).ok()?;
    Some(
        list.iter()
            .map(|entry| CryptoQuote {
                symbol: text(entry, "symbol").to_uppercase(),
                name: text(entry, "name"),
                price_usd: number(entry, "current_price"),
                change_24h: number(entry, "price_change_percentage_24h"),
                sparkline: entry
                    .get("sparkline_in_7d")
                    .and_then(|spark| spark.get("price"))
                    .and_then(Value::as_array)
                    .map(|prices| prices.iter().filter_map(Value::as_f64).collect())
                    .filter(|prices: &Vec<f64>| !prices.is_empty()),
            })
            .collect(),
    )
}

pub fn parse_fx(body: &str) -> Option<HashMap<String, f64>> {
    let json = serde_json::from_str::<Value>(body).ok()?;
    let rates = json.get("rates")?.as_object()?;
    let mut out = HashMap::new();
    for (code, value) in rates {
        if let Some(value) = value.as_f64() {
            out.insert(code.clone(), value);
        }
    }
    (!out.is_empty()).then_some(out)
}

pub fn parse_wallex(body: &str) -> Option<WallexQuote> {
    let json = serde_json::from_str::<Value>(body).ok()?;
    let stats = json
        .get("result")?
        .get("symbols")?
        .get("USDTTMN")?
        .get("stats")?;
    let toman = stats
        .get("lastPrice")
        .and_then(Value::as_str)
        .and_then(|value| value.parse().ok());
    Some(WallexQuote {
        toman_per_usdt: toman,
        change_24h: stats.get("24h_ch").and_then(Value::as_f64),
    })
}

pub fn parse_gold(body: &str) -> Option<f64> {
    let json = serde_json::from_str::<Value>(body).ok()?;
    json.get("price").and_then(Value::as_f64)
}

pub fn parse_yahoo(body: &str) -> YahooResult {
    let Ok(json) = serde_json::from_str::<Value>(body) else {
        return YahooResult::Malformed;
    };
    let Some(chart) = json.get("chart") else {
        return YahooResult::Malformed;
    };
    if let Some(code) = chart
        .get("error")
        .and_then(|error| error.get("code"))
        .and_then(Value::as_str)
    {
        return if code == "Not Found" {
            YahooResult::NoData
        } else {
            YahooResult::Malformed
        };
    }
    let Some(meta) = chart
        .get("result")
        .and_then(Value::as_array)
        .and_then(|results| results.first())
        .and_then(|result| result.get("meta"))
    else {
        return YahooResult::Malformed;
    };
    YahooResult::Quote(StockQuote {
        name: meta
            .get("longName")
            .and_then(Value::as_str)
            .or_else(|| meta.get("shortName").and_then(Value::as_str))
            .unwrap_or("")
            .to_owned(),
        price_usd: meta.get("regularMarketPrice").and_then(Value::as_f64),
        change_pct: meta
            .get("regularMarketChangePercent")
            .and_then(Value::as_f64),
    })
}

pub fn is_fiat(symbol: &str) -> bool {
    matches!(
        symbol.to_ascii_uppercase().as_str(),
        "USD"
            | "EUR"
            | "GBP"
            | "JPY"
            | "CHF"
            | "CAD"
            | "AUD"
            | "NZD"
            | "CNY"
            | "HKD"
            | "SGD"
            | "INR"
            | "AED"
            | "SAR"
            | "TRY"
            | "SEK"
            | "NOK"
            | "DKK"
            | "PLN"
            | "CZK"
            | "HUF"
            | "ZAR"
            | "BRL"
            | "MXN"
            | "KRW"
            | "IRR"
            | "IRT"
    )
}

fn is_gold(symbol: &str) -> bool {
    matches!(symbol.to_ascii_uppercase().as_str(), "GOLD" | "XAU")
}

/// Fetches every configured row. Source failures degrade to a note; a payload
/// with no rows at all is an error so the last good snapshot stands.
pub fn fetch(symbols: &[String], display: MarketCurrency) -> Result<MarketSnapshot, FetchError> {
    let symbols: Vec<String> = symbols
        .iter()
        .map(|symbol| symbol.trim().to_uppercase())
        .filter(|symbol| !symbol.is_empty())
        .collect();
    if symbols.is_empty() {
        return Err(FetchError::NotConfigured);
    }

    let mut notes: Vec<String> = Vec::new();
    let mut fx: Option<HashMap<String, f64>> = None;
    let mut wallex: Option<WallexQuote> = None;

    let needs_fx = symbols.iter().any(|symbol| is_fiat(symbol))
        || matches!(
            display,
            MarketCurrency::Eur | MarketCurrency::Cad | MarketCurrency::Aed
        );
    if needs_fx {
        match providers::get("https://open.er-api.com/v6/latest/USD", &[]) {
            Ok(body) => match parse_fx(&body) {
                Some(rates) => fx = Some(rates),
                None => notes.push("Exchange rates unreadable".into()),
            },
            Err(error) => notes.push(format!("Exchange rates: {}", error.message())),
        }
    }
    if matches!(display, MarketCurrency::Irt | MarketCurrency::Irr)
        || symbols.iter().any(|symbol| symbol == "USD")
    {
        match providers::get("https://api.wallex.ir/v1/markets", &[]) {
            Ok(body) => {
                wallex = parse_wallex(&body);
                if wallex.is_none() {
                    notes.push("Wallex unreadable".into());
                }
            }
            Err(error) => notes.push(format!("Wallex: {}", error.message())),
        }
    }

    let display_rate =
        display_rate(display, fx.as_ref(), wallex.as_ref()).ok_or(FetchError::InvalidPayload)?;

    let mut crypto_quotes: Vec<CryptoQuote> = Vec::new();
    let candidates: Vec<&String> = symbols
        .iter()
        .filter(|symbol| !is_fiat(symbol) && !is_gold(symbol))
        .collect();
    if !candidates.is_empty() {
        let query = candidates
            .iter()
            .map(|symbol| symbol.to_lowercase())
            .collect::<Vec<_>>()
            .join(",");
        let url = format!(
            "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&symbols={query}&price_change_percentage=24h&sparkline=true"
        );
        match providers::get(&url, &[]) {
            Ok(body) => match parse_coingecko(&body) {
                Some(quotes) => crypto_quotes = quotes,
                None => notes.push("CoinGecko unreadable".into()),
            },
            Err(error) => notes.push(format!("CoinGecko: {}", error.message())),
        }
    }

    let mut rows = Vec::new();
    let mut unresolved = Vec::new();
    for symbol in &symbols {
        if is_gold(symbol) {
            match providers::get("https://api.gold-api.com/price/XAU", &[]) {
                Ok(body) => match parse_gold(&body) {
                    Some(per_ounce) => rows.push(MarketRow {
                        symbol: symbol.clone(),
                        name: "Gold".into(),
                        kind: MarketKind::Gold,
                        price: per_ounce / 31.1035 * display_rate,
                        day_change_pct: None,
                        sparkline: None,
                    }),
                    None => notes.push("Gold unreadable".into()),
                },
                Err(error) => notes.push(format!("Gold: {}", error.message())),
            }
            continue;
        }
        if is_fiat(symbol) {
            let usd_per_unit = if symbol == "USD" {
                Some(1.0)
            } else {
                fx.as_ref()
                    .and_then(|rates| rates.get(symbol).copied())
                    .filter(|rate| *rate > 0.0)
                    .map(|rate| 1.0 / rate)
            };
            let Some(usd_per_unit) = usd_per_unit else {
                unresolved.push(symbol.clone());
                continue;
            };
            let day_change = if symbol == "USD" {
                wallex.as_ref().and_then(|quote| quote.change_24h)
            } else {
                None
            };
            rows.push(MarketRow {
                symbol: symbol.clone(),
                name: symbol.clone(),
                kind: MarketKind::Fiat,
                price: usd_per_unit * display_rate,
                day_change_pct: day_change,
                sparkline: None,
            });
            continue;
        }
        if let Some(quote) = crypto_quotes
            .iter()
            .find(|quote| quote.symbol.eq_ignore_ascii_case(symbol))
        {
            let Some(price_usd) = quote.price_usd else {
                unresolved.push(symbol.clone());
                continue;
            };
            rows.push(MarketRow {
                symbol: symbol.clone(),
                name: quote.name.clone(),
                kind: MarketKind::Crypto,
                price: price_usd * display_rate,
                day_change_pct: quote.change_24h,
                sparkline: quote
                    .sparkline
                    .as_ref()
                    .map(|points| points.iter().map(|point| point * display_rate).collect()),
            });
            continue;
        }
        match providers::get(
            &format!(
                "https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=1d"
            ),
            &[],
        ) {
            Ok(body) => match parse_yahoo(&body) {
                YahooResult::Quote(quote) => match quote.price_usd {
                    Some(price) => rows.push(MarketRow {
                        symbol: symbol.clone(),
                        name: if quote.name.is_empty() {
                            symbol.clone()
                        } else {
                            quote.name
                        },
                        kind: MarketKind::Stock,
                        price: price * display_rate,
                        day_change_pct: quote.change_pct,
                        sparkline: None,
                    }),
                    None => unresolved.push(symbol.clone()),
                },
                YahooResult::NoData | YahooResult::Malformed => unresolved.push(symbol.clone()),
            },
            Err(error) => {
                notes.push(format!("Yahoo: {}", error.message()));
                unresolved.push(symbol.clone());
            }
        }
    }

    if !unresolved.is_empty() {
        notes.push(format!("Unknown: {}", unresolved.join(", ")));
    }
    if rows.is_empty() {
        return Err(FetchError::InvalidPayload);
    }
    Ok(MarketSnapshot {
        display_currency: display,
        rows,
        note: (!notes.is_empty()).then(|| notes.join(" · ")),
    })
}

fn display_rate(
    display: MarketCurrency,
    fx: Option<&HashMap<String, f64>>,
    wallex: Option<&WallexQuote>,
) -> Option<f64> {
    match display {
        MarketCurrency::Usd => Some(1.0),
        MarketCurrency::Eur => fx?.get("EUR").copied(),
        MarketCurrency::Cad => fx?.get("CAD").copied(),
        MarketCurrency::Aed => fx?.get("AED").copied(),
        MarketCurrency::Irt => wallex?.toman_per_usdt,
        MarketCurrency::Irr => wallex?.toman_per_usdt.map(|toman| toman * 10.0),
    }
}

fn text(entry: &Value, key: &str) -> String {
    entry
        .get(key)
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_owned()
}

fn number(entry: &Value, key: &str) -> Option<f64> {
    entry.get(key).and_then(Value::as_f64)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_the_coingecko_contract() {
        let body = include_str!("../../../contracts/fixtures/coinGeckoMarkets.json");
        let quotes = parse_coingecko(body).expect("quotes");
        let bitcoin = quotes
            .iter()
            .find(|quote| quote.symbol == "BTC")
            .expect("btc");
        assert_eq!(bitcoin.name, "Bitcoin");
        assert!(bitcoin.price_usd.unwrap_or(0.0) > 0.0);
        assert!(bitcoin
            .sparkline
            .as_ref()
            .is_some_and(|points| !points.is_empty()));
    }

    #[test]
    fn parses_wallex_gold_and_fx() {
        let wallex = parse_wallex(include_str!(
            "../../../contracts/fixtures/wallexMarkets.json"
        ))
        .expect("wallex");
        assert!(wallex.toman_per_usdt.unwrap_or(0.0) > 0.0);
        assert_eq!(
            parse_gold(include_str!("../../../contracts/fixtures/goldXau.json")),
            Some(4644.399902)
        );
        let rates =
            parse_fx(include_str!("../../../contracts/fixtures/erApiLatest.json")).expect("rates");
        assert!(rates.get("EUR").copied().unwrap_or(0.0) > 0.0);
        assert!(rates.contains_key("CAD"));
    }

    #[test]
    fn parses_yahoo_quote_and_no_data() {
        let quote = parse_yahoo(include_str!(
            "../../../contracts/fixtures/yahoo_chart_aapl.json"
        ));
        match quote {
            YahooResult::Quote(quote) => {
                assert_eq!(quote.name, "Apple Inc.");
                assert_eq!(quote.price_usd, Some(316.22));
            }
            other => panic!("expected quote, got {other:?}"),
        }
        assert_eq!(
            parse_yahoo(include_str!(
                "../../../contracts/fixtures/yahoo_chart_unknown.json"
            )),
            YahooResult::NoData
        );
    }

    #[test]
    fn currency_labels_round_trip() {
        for currency in [
            MarketCurrency::Usd,
            MarketCurrency::Eur,
            MarketCurrency::Cad,
            MarketCurrency::Aed,
            MarketCurrency::Irr,
            MarketCurrency::Irt,
        ] {
            assert_eq!(MarketCurrency::from_label(currency.label()), Some(currency));
        }
    }

    #[test]
    fn classifies_symbols() {
        assert!(is_fiat("EUR"));
        assert!(is_fiat("irt"));
        assert!(is_gold("XAU"));
        assert!(!is_fiat("BTC"));
        assert!(!is_gold("AAPL"));
    }
}

#[cfg(test)]
mod search_tests {
    use super::{encode_query, parse_coin_search, parse_stock_search};

    #[test]
    fn parses_coin_search_in_server_order() {
        let body = r#"{"coins":[
          {"id":"bitcoin","symbol":"btc","name":"Bitcoin","market_cap_rank":1},
          {"id":"bitcoin-cash","symbol":"bch","name":"Bitcoin Cash","market_cap_rank":22}
        ]}"#;
        let hits = parse_coin_search(body).expect("hits");
        assert_eq!(hits[0].symbol, "BTC");
        assert_eq!(hits[0].rank, Some(1));
        assert_eq!(hits[1].name, "Bitcoin Cash");
        assert!(parse_coin_search("{}").is_none());
    }

    #[test]
    fn parses_stock_search_quotes() {
        let body = r#"{"quotes":[
          {"symbol":"AAPL","shortname":"Apple Inc.","quoteType":"EQUITY"},
          {"symbol":"APLE","shortname":"Apple Hospitality","quoteType":"EQUITY"}
        ]}"#;
        let hits = parse_stock_search(body).expect("hits");
        assert_eq!(hits[0].symbol, "AAPL");
        assert_eq!(hits[0].name, "Apple Inc.");
        assert!(parse_stock_search("{}").is_none());
    }

    #[test]
    fn query_encoding_keeps_alphanumerics() {
        assert_eq!(encode_query("bit coin&x"), "bit%20coin%26x");
    }
}
