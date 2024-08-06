use ./lib.nu *

let started = date now

print -e '- Loading $types'
let types = (open sde/fsd/types.yaml
  | transpose typeID data
  | flatten
  | update typeID { into int }
  | update name { get en }
  | each {
      smart-update description {
        get en? | default '<MISSING>' | str-wrap --wrap-at 10
      }
    }
  | each {
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
  | each {
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
  | each {
      smart-update descriptionID { get en }
      | smart-update displayNameID { get en }
    }
)

print -e '- Loading $metagroups'
let metagroups = (open sde/fsd/metaGroups.yaml
  | transpose metaGroupID data
  | update metaGroupID { into int }
  | flatten
  | each {
      smart-update nameID { get en }
      | smart-update descriptionID { get en }
    }
)

print -e '- Loading $groups'
let groups = (open sde/fsd/groups.yaml
  | transpose groupID data
  | update groupID { into int }
  | flatten
  | each { smart-update name { get en } }
)

let units = load-units

print -e '- Loading $marketGroups'
let marketGroups = (open sde/fsd/marketGroups.yaml
  | transpose marketGroupID data
  | update marketGroupID { into int }
  | flatten
  | each {
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
let expiry_anchor = ('2022-01-01' | into datetime)
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
    143 => { $expiry_anchor + ($'($in)hr' | into duration) } # datetime - a weird floating value between 17k and 20k
    _ => { $in }
  }
}
let detailed_types = ($types
  | left-join $dogmas typeID
  | each {
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
  | each {
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

def weapons [
  marketGroupName: string = 'Turrets & Launchers'
   --full
] {
  from-market $marketGroupName --full=$full
  | reject -i traits
  | if not $full {
      reject metaName
    } else { $in }
  | update dogmaAttributes {
      if not $full {
        where name !~ '^(requiredSkill|techLevel|metaLevelOld|typeColorScheme|chargeGroup|chargeSize).*$'
      } else { $in }
      | reject -i category
      | transpose -rdi
    }
  | flatten -a dogmaAttributes
}

print -e $'- Loaded in ((date now) - $started)'
