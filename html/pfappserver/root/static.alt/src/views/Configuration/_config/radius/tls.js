import i18n from '@/utils/locale'
import pfFormChosen from '@/components/pfFormChosen'
import pfFormInput from '@/components/pfFormInput'
import pfFormRangeToggle from '@/components/pfFormRangeToggle'
import { pfSearchConditionType as conditionType } from '@/globals/pfSearch'
import {
  attributesFromMeta,
  validatorsFromMeta
} from '../'
import {
  and,
  not,
  conditional,
  hasRadiusTlss,
  radiusTlsExists
} from '@/globals/pfValidators'
import {
  required
} from 'vuelidate/lib/validators'

export const columns = [
  {
    key: 'id',
    label: 'Identifier', // i18n defer
    sortable: true,
    visible: true
  },
  {
    key: 'certificate_profile',
    label: 'Certificate Profile', // i18n defer
    sortable: true,
    visible: true
  },
  {
    key: 'ocsp',
    label: 'OCSP Profile', // i18n defer
    sortable: true,
    visible: true
  },
  {
    key: 'buttons',
    label: '',
    locked: true
  }
]

export const fields = [
  {
    value: 'id',
    text: i18n.t('Identifier'),
    types: [conditionType.SUBSTRING]
  }
]

export const config = () => {
  return {
    columns,
    fields,
    rowClickRoute (item) {
      return { name: 'radiusTls', params: { id: item.id } }
    },
    searchPlaceholder: i18n.t('Search by identifier'),
    searchableOptions: {
      searchApiEndpoint: 'config/radiusd/tls_profiles',
      defaultSortKeys: ['id'],
      defaultSearchCondition: {
        op: 'and',
        values: [{
          op: 'or',
          values: [
            { field: 'id', op: 'contains', value: null }
          ]
        }]
      },
      defaultRoute: { name: 'radiusTlss' }
    },
    searchableQuickCondition: (quickCondition) => {
      return {
        op: 'and',
        values: [
          {
            op: 'or',
            values: [
              { field: 'id', op: 'contains', value: quickCondition }
            ]
          }
        ]
      }
    }
  }
}

export const view = (form = {}, meta = {}) => {
  const {
    isDeletable = false
  } = meta

  return [
    {
      tab: null,
      rows: [
        {
          label: i18n.t('Identifier'),
          cols: [
            {
              namespace: 'id',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'id'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('Certificate Profile'),
          cols: [
            {
              namespace: 'certificate_profile',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'certificate_profile'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('DH File'),
          cols: [
            {
              namespace: 'dh_file',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'dh_file'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('CA Path'),
          cols: [
            {
              namespace: 'ca_path',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'ca_path'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('Cipher List'),
          cols: [
            {
              namespace: 'cipher_list',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'cipher_list'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('ECDH Curve'),
          cols: [
            {
              namespace: 'ecdh_curve',
              component: pfFormInput,
              attrs: {
                ...attributesFromMeta(meta, 'ecdh_curve'),
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('Disable TLSv1.2'),
          cols: [
            {
              namespace: 'disable_tlsv1_2',
              component: pfFormRangeToggle,
              attrs: {
                values: { checked: 'yes', unchecked: 'no' },
                disabled: isDeletable
              }
            }
          ]
        },
        {
          label: i18n.t('OCSP Profile'),
          cols: [
            {
              namespace: 'ocsp',
              component: pfFormChosen,
              attrs: {
                ...attributesFromMeta(meta, 'ocsp'),
                disabled: isDeletable
              }
            }
          ]
        }
      ]
    }
  ]
}

export const validators = (form = {}, meta = {}) => {
  const {
    isNew = false,
    isClone = false
  } = meta
  return {
    id: {
      ...validatorsFromMeta(meta, 'id', i18n.t('Identifier')),
      ...{
        [i18n.t('TLS profile exists.')]: not(and(required, conditional(isNew || isClone), hasRadiusTlss, radiusTlsExists))
      }
    }
  }
}