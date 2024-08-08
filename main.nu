use ./lib.nu *

let started = date now
const damage_types = [emDamage thermalDamage kineticDamage explosiveDamage]

let types = load-cache '.types.nuon' '$types' {||
  (open sde/fsd/types.yaml
  | transpose typeID data
  | where data.published == true
  | flatten
  | update typeID { into int }
  | update name { get en }
  | par-each {
      smart-update description {
        get en? | default '<MISSING>' | str-wrap --wrap-at 10
      }
    }
  | par-each {
      smart-update traits {
        smart-update roleBonuses {
          update bonusText { get en }
        }
        | smart-update miscBonuses {
            update bonusText { get en }
          }
        | smart-update types {
            transpose typeID data
            | update data {
                update bonusText { get en }
              }
            | flatten -a
          }
      }
    }
  )
}

let units = load-units

let dogmas = load-cache '.dogmas.nuon' '$dogmas' {||
  open sde/fsd/typeDogma.yaml
  | transpose typeID dogma
  | flatten
  | update typeID { into int }
}

let attributes = load-cache '.attributes.nuon' '$attributes' {||
  open sde/fsd/dogmaAttributes.yaml
  | transpose attributeID data
  | get data
  | reject -i tooltipDescriptionID tooltipTitleID
  | par-each {
      smart-update displayNameID { get en }
      | smart-update tooltipDescriptionID { get en }
      | smart-update tooltipTitleID { get en }
    }
}

let attribute_categories = load-cache '.attribute_categories.nuon' '$attribute_categories' {||
  open sde/fsd/dogmaAttributeCategories.yaml
  | transpose attributeCategoryID data
  | update attributeCategoryID { into int }
  | flatten
}

let effects = load-cache '.effects.nuon' '$effects' {||
  open sde/fsd/dogmaEffects.yaml
  | transpose effectid data
  | get data
  | par-each {
      smart-update descriptionID { get en }
      | smart-update displayNameID { get en }
    }
}

let metagroups = load-cache '.metagroups.nuon' '$metagroups' {||
  open sde/fsd/metaGroups.yaml
  | transpose metaGroupID data
  | update metaGroupID { into int }
  | flatten
  | par-each {
      smart-update nameID { get en }
      | smart-update descriptionID { get en }
    }
}

let groups = load-cache '.groups.nuon' '$groups' {||
  open sde/fsd/groups.yaml
  | transpose groupID data
  | update groupID { into int }
  | flatten
  | par-each { smart-update name { get en } }
}

let market_groups = load-cache '.market_groups.nuon' '$market_groups' {||
  open sde/fsd/marketGroups.yaml
  | transpose marketGroupID data
  | update marketGroupID { into int }
  | flatten
  | par-each {
      smart-update descriptionID { get en }
      | smart-update nameID { get en }
      | rename -c { nameID: name }
      | if 'descriptionID' in $in {
          rename -c { descriptionID: description }
        } else { $in }
    }
  | select marketGroupID name parentGroupID?
}

let detailed_types = load-cache '.detailed_types.nuon' '$detailed_types' {||

  def resolve-market [
    marketGroupID: int
  ] {
    let resolved = $market_groups | where marketGroupID == $marketGroupID | first | select name parentGroupID?
    
    if $resolved.parentGroupID? != null {
      [$resolved.name] | prepend [(resolve-market $resolved.parentGroupID)] | flatten -a
    } else {
      [$resolved.name]
    }
  }

  def render-traits [] {
    let traits = $in

    def format-bonus [] {
      let row = $in | update bonusText { str replace -ra '<[^>]+>([^<]+)</[^>]+>' '$1' }
      if ('bonus' in $row) {
        $'($row.bonus)($units | where unitID == $row.unitID | first | get displayName) ($row.bonusText)'
      } else {
        $'($row.bonusText)'
      }
    }

    let fixed_bonuses = (
      ($traits.roleBonuses? | default [])
      | append ($traits.miscBonuses? | default [])
      | each { ($in | format-bonus) | if ($in | str trim | is-empty) { null } else { '- ' + $in } }
    )
    let perskill_bonuses = (
      if ('types' in $traits) {
        $traits.types
        | join -l ($types | select name typeID | rename -c { name: skill }) typeID
        | each { $'- Per ($in.skill): ($in | format-bonus)' }
      } else { [] }
    )
    $fixed_bonuses | append $perskill_bonuses | str join "\n" | default ''
  }

  ($types |
    | left-join $dogmas typeID
    | par-each { |type|
        $type | smart-update dogmaAttributes {
          left-join $attributes attributeID
          | reject attributeID
          | left-join ($attribute_categories
            | rename -c {
                attributeCategoryID: categoryID
                name: category
              }
            ) categoryID
          | reject -i categoryID
          | update value { |row|
              let value = $row.value | default $row.defaultValue
              if 'unitID' in $row {
                $value | convert-value $row.unitID
              } else {
                $value
              }
            }
          | select name value category?
        }
        | smart-update dogmaEffects {
            left-join $effects effectID | get effectName
          }
        | smart-update traits {
            try { render-traits } catch { print -e $"- render-traits failed for \n($type | table -ed 2)" ; exit 1 }
          }
      }
    | par-each {
        if 'marketGroupID' in $in {
          insert market { |row| resolve-market $row.marketGroupID | str join " -> "}
        } else {}
      }
    | left-join ($groups | rename -c { name: group } | select groupID group) groupID
    | left-join ($metagroups | rename -c { nameID: metaName }) metaGroupID
    | select typeID name group market? metaName description? dogmaAttributes? dogmaEffects? traits?
  )
}

let turrets = load-cache '.turrets.nuon' '$turrets' {||
  weapon-turrets -c { true }
}

# UX

def from-market [
  market_group_name: string # regex
  --not
] {
  $detailed_types
  | where market? != null
  | if $not {
      where market !~ $market_group_name
    } else {
      where market =~ $market_group_name
    }
}

def weapon-launchers [
] {
}

def weapon-smartbombs [
] {
}

def weapon-precursors [
] {
}

def weapon-supers [
] {
}

def weapon-vortons [
] {
}

def weapon-bomblaunchers [
] {
}

# List turrets under a specific market group
def weapon-turrets [
  market_group_name: string = '^Ship Equipment -> Turrets & Launchers -> (Projectile|Hybrid|Energy) Turrets' # regex
  --charges (-c): closure # predicate filtering out weapons before adding charges info, one weapon record as input
] {
  from-market $market_group_name
  | reject -i traits
  | if $charges != null {
      filter $charges
      | each { |row|
          if 'chargeSize' in $row.dogmaAttributes.name {
            let row = $row | insert chargeSize {
              $row.dogmaAttributes
                | where name == 'chargeSize'
                | first
                | get value
            }
            $row
            | insert charges {
                $row.dogmaAttributes
                | where name =~ '^chargeGroup'
                | par-each { |attr|
                    let charge_group_id = $attr | get value
                    let charges = $types
                    | where groupID == $charge_group_id
                    | select typeID
                    | join $detailed_types typeID
                    | filter {
                        get dogmaAttributes
                        | select name value
                        | { name: 'chargeSize' value: $row.chargeSize } in $in
                      }
                    $charges | update dogmaAttributes {
                      where name in ([
                        emDamage
                        explosiveDamage
                        kineticDamage
                        thermalDamage
                        weaponRangeMultiplier # Range Bonus (?)
                        fallofMultiplier
                        trackingSpeedMultiplier
                      ])
                      | select name value
                      | transpose -rdi
                    }
                    | select name dogmaAttributes
                    | flatten -a dogmaAttributes
                }
                | flatten
              }
          } else { $row }
        }
    } else { $in }
  | reject metaName
  | update dogmaAttributes {
      where name in ([
        maxRange # Optimal Range
        falloff
        trackingSpeed
        speed # Rate of Fire
        reloadTime
        damageMultiplier # Damage Modifier
        damageMultiplierBonus # Damage Multiplier Bonus
        overloadDamageModifier # Overload Damage Bonus
        optimalSigRadius
      ])
      | select name value
      | transpose -rdi
    }
  | flatten -a dogmaAttributes
}

# Turn the output of a `weapon -c` into simulated combat stats
def sim-turrets [] {
  each { |w|
    insert combatsim {
      $w.charges
      | each { |c|
        {
          charge: $c.name
          damage: (
            $damage_types | reduce -f {} { |damage_type, acc|
              $acc | insert $damage_type {(
                ($c | get $damage_type)
                * ($w.damageMultiplier)
                * ($w.damageMultiplierBonus? | default 1)
                / ($w.speed / 1000)
              )}
            }
          )
          optimal: ($w.maxRange * ($c.weaponRangeMultiplier? | default 1))
          falloff: ($w.falloff * ($c.fallofMultiplier? | default 1))
          tracking: ($w.trackingSpeed * ($c.trackingSpeedMultiplier? | default 1))
        }
        | flatten -a damage
        | insert totalDamage { $in.emDamage + $in.thermalDamage + $in.kineticDamage + $in.explosiveDamage }
        | select charge optimal falloff tracking totalDamage emDamage thermalDamage kineticDamage explosiveDamage
      }
      | flatten
    }
    | select name chargeSize combatsim
  }
}

const shield_res_cols = [ShEm ShTh ShKi ShEx]
const armor_res_cols = [ArEm ArTh ArKi ArEx]
const hull_res_cols = [HuEm HuTh HuKi HuEx]

let ship_attribute_map = {
  shieldCapacity: ShHP
  shieldEmDamageResonance: ShEm
  shieldThermalDamageResonance: ShTh
  shieldKineticDamageResonance: ShKi
  shieldExplosiveDamageResonance: ShEx
  shieldRechargeRate: ShRegen
  armorHP: ArHP
  armorEmDamageResonance: ArEm
  armorThermalDamageResonance: ArTh
  armorKineticDamageResonance: ArKi
  armorExplosiveDamageResonance: ArEx
  hp: HuHP
  emDamageResonance: HuEm
  thermalDamageResonance: HuTh
  kineticDamageResonance: HuKi
  explosiveDamageResonance: HuEx
  maxVelocity: Vel
  agility: Agi
  maxTargetRange: Range
  warpSpeedMultiplier: Warp
}
let ship_attribute_map_table = $ship_attribute_map | transpose old new

def ships [
  market_group_name: string = '^Ships ->' # regex
] {
  from-market $market_group_name
  | upsert traits { default '' }
  | reject -i dogmaEffects
  | update dogmaAttributes {
      where name in ($ship_attribute_map_table | get old)
      | update name { |row| $ship_attribute_map | get $row.name }
      | select name value
      | transpose -rdi
    }
  | flatten -a dogmaAttributes
  | select ...(
      ($in | columns | filter { $in not-in ($ship_attribute_map_table | get new) })
      | append ($ship_attribute_map_table | get new)
      | filter { $in != 'traits' }
      | append 'traits'
    )
  | each { |ship|
      let ship = [ShEm ShTh ShKi ShEx ArEm ArTh ArKi ArEx HuEm HuTh HuKi HuEx] | reduce -f $ship { |resist, ship|
        $ship | update $resist { 1 - $in | $in * 100 | into int }
      }
      let ship = [ShHP ArHP HuHP Vel Range ShRegen] | reduce -f $ship { |col, ship|
        $ship | update $col { into int }
      }
      $ship
    }
}

def move-last [colname: string] {
  let table = $in
  $table | move $colname --after ($table | columns | last)
}

# Add `simship` section on the output of `ships`
def sim-ships [
  --all
  --shields (-s)
  --no-shields (-S)
  --armor (-a)
  --no-armor (-A)
  --hull (-h)
  --no-hull (-H)
  --protection (-p)
  --mobility (-m)
  --no-mobility (-M)
  --dbg
] {
  let input = $in
  def dbg [comment] {
    if $dbg {
      xray $comment
    }
  }
  $input | each { |ship|
    $ship.traits
    | smart-parse '^- (?<percent>\d+)% bonus to all (?<target>hull|shield|armor, shield, and hull|shield and armor) resistances'
    | append (
        $ship.traits
        | smart-parse '^- Per [^:]+: (?<percent>\d+)% bonus to all (?<target>hull|shield|armor|armor, shield, and hull|shield and armor) resistances'
        | update percent { into int | $in * 5 }
      )
    | update percent { into int }
    | update target { split words | filter { $in != 'and' } }
    | flatten
    | if ($in | is-not-empty) {
        smart-group-by target
        | flatten -a
        | update target {
            match $in {
              "shield" => { $shield_res_cols }
              "armor" => { $armor_res_cols }
              "hull" => { $hull_res_cols }
            }
          }
        | flatten
        | reduce -f $ship { |bonus, ship|
            $ship | update $bonus.target { $in + ((100 - $in) * ($bonus.percent / 100)) }
          }
      } else { $ship }
    | insert ArRes { $in.ArEm + $in.ArTh + $in.ArKi + $in.ArEx }
    | insert ShRes { $in.ShEm + $in.ShTh + $in.ShKi + $in.ShEx }
    | insert ArShRes { $in.ArRes + $in.ShRes }
    | move-last traits
  }
}

print -e $'- Loaded ($detailed_types | length) types in ((date now) - $started)'
