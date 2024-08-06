use ./lib.nu *

let started = date now

print -e '- Loading $types'
let types = (open sde/fsd/types.yaml
  | transpose typeID data
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
    }
)

print -e '- Resolving $detailed_types'
def resolve-market [
  marketGroupID: int
] {
  let resolved = $marketGroups | where marketGroupID == $marketGroupID | first | select nameID parentGroupID?
  
  if $resolved.parentGroupID? != null {
    [$resolved.nameID] | prepend [(resolve-market $resolved.parentGroupID)] | flatten -a
  } else {
    [$resolved.nameID]
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
        insert market { |row| resolve-market $row.marketGroupID }
      } else {}
    }
  | select typeID name groupName market? metaName description? dogmaAttributes? dogmaEffects? traits?
)

# UX

def from-market [
  marketGroupName: string
  --full
] {
  $detailed_types
  | where market? != null
  | filter { $marketGroupName in $in.market }
  | if not $full {
      reject -i typeID description market
    } else { $in }
}

# List all weapons under a specific market group
def weapons [
  marketGroupName: string = 'Turrets & Launchers'
  --charges (-c): closure # predicate filtering out weapons before adding charges info, one weapon record as input
  --full
] {
  from-market $marketGroupName --full=$full
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
              $types
              | where groupID == $charge_group_id
              | select typeID
              | join $detailed_types typeID
              | filter {
                  get dogmaAttributes
                  | select name value
                  | { name: 'chargeSize' value: $charge_size } in $in
                }
              | update dogmaAttributes {
                  where name =~ '^(emDamage|explosiveDamage|kineticDamage|thermalDamage|weaponRangeMultiplier|trackingSpeedMultiplier)$'
                  | select name value
                }
              | select name dogmaAttributes
              | transpose -rdi
            }
          }
        }
    } else if not $full {
      reject metaName
      | update dogmaAttributes {
          where name !~ '^(requiredSkill|techLevel|metaLevelOld|typeColorScheme|chargeGroup|chargeSize)'
          | select name value
          | transpose -rdi
        }
    }
  | flatten -a dogmaAttributes
}

print -e $'- Loaded ($detailed_types | length) types in ((date now) - $started)'
