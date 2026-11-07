//! What the native shell draws itself, as it declares when it starts.

use std::fmt;
use std::str::FromStr;

use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// A part of the app's chrome the shell can draw natively.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Feature {
    /// The app's native panels ([`super::PanelInfo`]): inspectors and tool popovers.
    Panels,
    /// The menu bar ([`super::MenuBar`]).
    Menus,
    /// The tool rail ([`super::ToolPalette`]).
    Rail,
    /// Status messages and progress ([`super::Status`]).
    Status,
}

impl Feature {
    /// Every feature, in wire order.
    pub const ALL: [Self; 4] = [Self::Panels, Self::Menus, Self::Rail, Self::Status];

    const fn name(self) -> &'static str {
        match self {
            Self::Panels => "panels",
            Self::Menus => "menus",
            Self::Rail => "rail",
            Self::Status => "status",
        }
    }

    const fn bit(self) -> u8 {
        1 << self as u8
    }
}

impl fmt::Display for Feature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.name())
    }
}

/// A name that isn't one of the [`Feature`]s.
#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
#[error("`{0}` isn't a shell feature")]
pub struct UnknownFeature(String);

impl FromStr for Feature {
    type Err = UnknownFeature;

    fn from_str(name: &str) -> Result<Self, UnknownFeature> {
        Self::ALL.into_iter().find(|f| f.name() == name).ok_or_else(|| UnknownFeature(name.to_owned()))
    }
}

/// The parts of the chrome a shell draws: a set of [`Feature`]s. On the wire, a list of their
/// names; a name this kit doesn't know (a newer shell's) is left out.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct ShellFeatures(u8);

impl ShellFeatures {
    /// No features: the app draws all its chrome itself.
    #[must_use]
    pub const fn none() -> Self {
        Self(0)
    }

    /// Whether the shell draws `feature`.
    #[must_use]
    pub const fn contains(self, feature: Feature) -> bool {
        self.0 & feature.bit() != 0
    }

    /// Add `feature`.
    pub fn insert(&mut self, feature: Feature) {
        self.0 |= feature.bit();
    }

    /// Whether the shell draws nothing itself.
    #[must_use]
    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    /// The features, in [`Feature::ALL`]'s order.
    pub fn iter(self) -> impl Iterator<Item = Feature> {
        Feature::ALL.into_iter().filter(move |f| self.contains(*f))
    }
}

impl FromIterator<Feature> for ShellFeatures {
    fn from_iter<I: IntoIterator<Item = Feature>>(iter: I) -> Self {
        let mut set = Self::none();
        for feature in iter {
            set.insert(feature);
        }
        set
    }
}

impl<const N: usize> From<[Feature; N]> for ShellFeatures {
    fn from(features: [Feature; N]) -> Self {
        features.into_iter().collect()
    }
}

impl Serialize for ShellFeatures {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.collect_seq(self.iter())
    }
}

impl<'de> Deserialize<'de> for ShellFeatures {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let names = Vec::<String>::deserialize(deserializer)?;
        Ok(names.iter().filter_map(|name| name.parse().map_err(|e: UnknownFeature| log::debug!("craft-mobile: {e}; ignored")).ok()).collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn features_are_a_set() {
        let mut set = ShellFeatures::from([Feature::Rail, Feature::Panels, Feature::Rail]);
        assert!(set.contains(Feature::Panels) && set.contains(Feature::Rail));
        assert!(!set.contains(Feature::Menus));
        assert_eq!(set.iter().collect::<Vec<_>>(), [Feature::Panels, Feature::Rail]);
        set.insert(Feature::Status);
        assert!(set.contains(Feature::Status));
        assert!(ShellFeatures::default().is_empty());
        assert_eq!(ShellFeatures::default(), ShellFeatures::none());
    }

    #[test]
    fn features_are_names_on_the_wire_and_unknown_ones_are_left_out() {
        let all = ShellFeatures::from(Feature::ALL);
        assert_eq!(serde_json::to_value(all).unwrap(), json!(["panels", "menus", "rail", "status"]));
        let parsed: ShellFeatures = serde_json::from_value(json!(["status", "hologram", "menus"])).unwrap();
        assert_eq!(parsed, ShellFeatures::from([Feature::Menus, Feature::Status]));
        assert!(serde_json::from_value::<ShellFeatures>(json!("menus")).is_err(), "a list, not a name");
    }

    #[test]
    fn a_feature_parses_and_prints_its_name() {
        for f in Feature::ALL {
            assert_eq!(f.to_string().parse::<Feature>(), Ok(f));
        }
        assert_eq!("dock".parse::<Feature>(), Err(UnknownFeature("dock".into())));
    }
}
