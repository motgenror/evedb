use ./lib.nu *

let started = date now

print -e '- Loading $types'
let types = (open sde/fsd/types.yaml
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

print -e '- Loading $dogmas'
let dogmas = open sde/fsd/typeDogma.yaml | transpose typeID dogma | flatten | update typeID { into int }

print -e '- Loading $attributes'
let attributes = (open sde/fsd/dogmaAttributes.yaml
  | transpose attributeID data
  | get data
  | reject -i tooltipDescriptionID tooltipTitleID
  | par-each {
      smart-update displayNameID { get en }
      #| smart-update tooltipDescriptionID { get en }
      #| smart-update tooltipTitleID { get en }
    }
  #| select attributeID name displayNameID? description? tooltipDescriptionID? tooltipTitleID? categoryID? dataType highIsGood defaultValue unitID? maxAttributeID?
)

print -e '- Loading $attributeCategories'
let attributeCategories = (open sde/fsd/dogmaAttributeCategories.yaml
  | transpose attributeCategoryID data
  | update attributeCategoryID { into int }
  | flatten
)

print -e '- Loading $effects'
let effects = (open sde/fsd/dogmaEffects.yaml
  | transpose effectid data
  | get data
  | par-each {
      smart-update descriptionID { get en }
      | smart-update displayNameID { get en }
    }
)

print -e '- Loading $metagroups'
let metagroups = (open sde/fsd/metaGroups.yaml
  | transpose metaGroupID data
  | update metaGroupID { into int }
  | flatten
  | par-each {
      smart-update nameID { get en }
      | smart-update descriptionID { get en }
    }
)

print -e '- Loading $groups'
let groups = (open sde/fsd/groups.yaml
  | transpose groupID data
  | update groupID { into int }
  | flatten
  | par-each { smart-update name { get en } }
)

let units = load-units

print -e '- Loading $marketGroups'
let marketGroups = (open sde/fsd/marketGroups.yaml
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
)

print -e '- Resolving $detailed_types'
def resolve-market [
  marketGroupID: int
] {
  let resolved = $marketGroups | where marketGroupID == $marketGroupID | first | select name parentGroupID?
  
  if $resolved.parentGroupID? != null {
    [$resolved.name] | prepend [(resolve-market $resolved.parentGroupID)] | flatten -a
  } else {
    [$resolved.name]
  }
}
let expiry_anchor = ('1970-01-01' | into datetime)
def convert-value [unitID: int] {
  match $unitID {
    115 => { into int } # groupID
    116 => { into int } # typeID
    119 => { into int } # attributeID
    129 => { $'($in)hr' | into duration } # hours
    136 => { into int } # slot
    137 => { into bool } # boolean
    139 => { into bool } # plus sign
    141 => { into int } # hardpoints
    142 => { into int } # 1=Male 2=Unisex 3=Female
    143 => { $expiry_anchor + ($'($in)day' | into duration) } # days since UNIX epoch
    _ => { $in }
  }
}
let detailed_types = ($types
  | left-join $dogmas typeID
  | par-each {
      smart-update dogmaAttributes {
        left-join $attributes attributeID
        | reject attributeID
        | left-join ($attributeCategories
          | rename -c {
              attributeCategoryID: categoryID
              name: category
            }
          ) categoryID
        | reject -i categoryID
        | update value { |row|
            if 'unitID' in $row {
              $row.value | convert-value $row.unitID
            } else {
              $row.value
            }
          }
        | select name value category?
      }
      | smart-update dogmaEffects {
          left-join $effects effectID | get effectName
        }
    }
  | left-join ($groups | rename -c { name: groupName } | select groupID groupName) groupID
  | left-join ($metagroups | rename -c { nameID: metaName }) metaGroupID
  | par-each {
      if 'marketGroupID' in $in {
        insert market { |row| resolve-market $row.marketGroupID | str join " -> "}
      } else {}
    }
  | select typeID name groupName market? metaName description? dogmaAttributes? dogmaEffects? traits?
)

# UX

def from-market [
  market_group_name: string # regex
  --full
  --not
] {
  $detailed_types
  | where market? != null
  | if $not {
      where market !~ $market_group_name
    } else {
      where market =~ $market_group_name
    }
  | if not $full {
      reject -i typeID description market dogmaEffects?
    } else { $in }
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
      | insert charges { |row|
          if 'chargeSize' not-in $row.dogmaAttributes.name {
            null
          } else {
            let charge_size = $row.dogmaAttributes | where name == 'chargeSize' | first | get value
            $row.dogmaAttributes | where name =~ '^chargeGroup' | par-each { |attr|
              let charge_group_id = $attr | get value
              let charges = $types
              | where groupID == $charge_group_id
              | select typeID
              | join $detailed_types typeID
              | filter {
                  get dogmaAttributes
                  | select name value
                  | { name: 'chargeSize' value: $charge_size } in $in
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

def attr-value [attr_name: string] {
  get -i $attr_name
  | default (do {
      let attr = $attributes | where name == $attr_name | first
      $attr | get defaultValue | convert-value $attr.unitID
    })
}

# Turn the output of a `weapon -c` into simulated combat stats
def sim-turrets [] {
  par-each { |w|
    insert combatsim {
      $w.charges | par-each { |c| {
        charge: $c.name
        damage: ([emDamage thermalDamage kineticDamage explosiveDamage] | par-each { |damage_type| {
          $damage_type: (
            ($c | attr-value $damage_type)
            * ($w | attr-value damageMultiplier)
            * ($w | attr-value damageMultiplierBonus)
            / (($w | attr-value speed) / 1000)
          )
        }})
        optimal: (($w | attr-value maxRange) * ($c | attr-value weaponRangeMultiplier))
        falloff: (($w | attr-value falloff) * ($c | attr-value fallofMultiplier)) # fallof - not a typo
        tracking: (($w | attr-value trackingSpeed) * ($c | attr-value trackingSpeedMultiplier))
      }}
    }
  }
}

print -e $'- Loaded ($detailed_types | length) types in ((date now) - $started)'
